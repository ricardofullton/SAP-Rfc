#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define MAX_PARA 64

#define RFCIMPORT     0
#define RFCEXPORT     1
#define RFCTABLE      2


#define BUF_SIZE 8192

#define RFC_WAIT_TIME 10


#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>

  
/* SAP flag for Windows NT or 95 */
#ifdef _WIN32
#  ifndef SAPonNT
#    define SAPonNT
#  endif
#endif

#include "saprfc.h"
#include "sapitab.h"

#if defined(SAPonNT)
#include "windows.h"
#endif

/* name of installed function for global callback in tRFC */
char name_user_global_server[31] = "%%USER_GLOBAL_SERVER";

/* global hash of interfaces */
HV* p_iface_hash;

/* global pointers to saprfc object */
SV* global_saprfc;
HV* p_saprfc;

/* global reference to main loop callback for registered RFC */
SV* sv_callback;

/* the current RFC_TID  */
RFC_TID current_tid;


/*
 * local prototypes & declarations
 */

static RFC_RC DLL_CALL_BACK_FUNCTION handle_request( RFC_HANDLE handle, SV* sv_iface );
static RFC_RC DLL_CALL_BACK_FUNCTION do_docu( RFC_HANDLE handle );
static SV* call_handler(SV* sv_callback_handler, SV* sv_iface, SV* sv_data);
RFC_RC loop_callback(SV* sv_callback_handler, SV* sv_self);
void get_attributes(RFC_HANDLE rfc_handle, HV* hv_sysinfo);
static int  DLL_CALL_BACK_FUNCTION  TID_check(RFC_TID tid);
static void DLL_CALL_BACK_FUNCTION  TID_commit(RFC_TID tid);
static void DLL_CALL_BACK_FUNCTION  TID_confirm(RFC_TID tid);
static void DLL_CALL_BACK_FUNCTION  TID_rollback(RFC_TID tid);
static RFC_RC DLL_CALL_BACK_FUNCTION user_global_server(RFC_HANDLE rfc_handle);
static char *user_global_server_docu(void);
static RFC_RC install_docu    ( RFC_HANDLE handle );
static char * do_docu_docu( void );


/* store a reference to the documentation array ref */
SV* sv_store_docu;


/* standard error call back handler - installed into connnection object */
static void  DLL_CALL_BACK_FUNCTION  rfc_error( char * operation ){
  RFC_ERROR_INFO_EX  error_info;
  
  RfcLastErrorEx(&error_info);
  croak( "RFC Call/Exception: %s \tError group: %d \tKey: %s \tMessage: %s",
      operation,
      error_info.group, 
      error_info.key,
      error_info.message );

/*
  RFC_ERROR_INFO  error_info;
  
  RfcLastError(&error_info);
  croak( "RFC Call/Key: %s \tStatus: %s \tMessage: %s\tInternal State:%s",
      error_info.key,
      error_info.status, 
      error_info.message,
      error_info.intstat );
      */

}


/* build a connection to an SAP system */
SV*  MyBcdToChar(SV* sv_bcd){
  int   rc,
        bcd_char_len,
        bcd_num_len,
        decimal_no;

  char           bcd_char[33];
  unsigned char  bcd_num[16];

  char * ptr;

  bcd_char_len = 4;
  bcd_num_len = 3;
  decimal_no = 1;
  memset(bcd_num+0, 0, sizeof(bcd_num));
  memset(bcd_char+0, 0, sizeof(bcd_char));
  //Copy(SvPV( sv_bcd, 2 ), (char *) bcd_num, 2, char);
  memcpy(bcd_num+0, SvPV(sv_bcd, SvCUR(sv_bcd)), 3);

  //rc = RfcConvertBcdToChar((RFC_BCD *) SvPV(sv_bcd, SvCUR(sv_bcd)),
  rc = RfcConvertBcdToChar((RFC_BCD *) bcd_num,
                           bcd_num_len,
                           decimal_no,
                           (RFC_CHAR *) bcd_char,
                           bcd_char_len);
  //memset(bcd_char+0, 0, 32 + 1);
  fprintf(stderr, "new bcd: %s#\n", bcd_char);
  return newSViv(1);
}


/* build a connection to an SAP system */
SV*  MyConnect(SV* connectstring){

    RFC_ENV            new_env;
    RFC_HANDLE         handle;
    RFC_ERROR_INFO_EX  error_info;
    /* RFC_ERROR_INFO  error_info; */
    
    new_env.allocate = NULL;
    new_env.errorhandler = rfc_error;
    RfcEnvironment( &new_env );

    /* fprintf(stderr, "%s\n", SvPV(connectstring, SvCUR(connectstring)));
    char * enc;
    char * Pass = "bl0wfish";
    RfcPasswordEnc(Pass, enc); 
    fprintf(stderr, "passowrd %s\n", enc); */
    
    handle = RfcOpenEx(SvPV(connectstring, SvCUR(connectstring)),
		       &error_info);

    if (handle == RFC_HANDLE_NULL){
	RfcLastErrorEx(&error_info);
        croak( "RFC Call/Exception: Connection Failed \tError group: %d \tKey: %s \tMessage: %s",
            error_info.group, 
            error_info.key,
            error_info.message );
  
    /*
        RfcLastError(&error_info);
        croak( "RFC Call/Key: %s \tStatus: %s \tMessage: %s\tInternal State:%s",
            error_info.key,
            error_info.status, 
            error_info.message,
            error_info.intstat );
	    */
    };
 
    return newSViv( ( int ) handle );
    
}



/* Disconnect from an SAP system */
SV*  MyDisconnect(SV* sv_handle){

    RFC_HANDLE         handle = SvIV( sv_handle );
    
    RfcClose( handle ); 
    return newSViv(1);

}

SV* MyGetTicket(SV* sv_handle){
    RFC_HANDLE handle;
    RFC_RC rc;
    RFC_ERROR_INFO_EX  error_info;
    char ticket[4096];
    HV* hash = newHV();

    handle = SvIV( sv_handle );

    rc = RfcGetTicket( handle, (RFC_CHAR *)&ticket );

    /* check the return code - if necessary construct an error message */
    if ( rc != RFC_OK ){
        RfcLastErrorEx( &error_info );
        hv_store(  hash, (char *) "__RETURN_CODE__", 15,
		      newSVpvf( "EXCEPT\t%s\tGROUP\t%d\tKEY\t%s\tMESSAGE\t%s", "RfcGetTicket", error_info.group, error_info.key, error_info.message ),
		      0 );
    } else {
        hv_store(  hash,  (char *) "__RETURN_CODE__", 15, newSVpvf( "%d", RFC_OK ), 0 );
        hv_store(  hash,  (char *) "TICKET", 6, newSVpvf( "%s", ticket ), 0 );
    };
    return newRV_noinc( (SV*) hash);
}


/* create a parameter space and zero it */
static void * make_space( SV* length ){

    char * ptr;
    int len = SvIV( length );
    
    ptr = malloc( len + 1 );
    if ( ptr == NULL )
	return 0;
    memset(ptr, 0, len + 1);
    return ptr;

}


/* copy the value of a parameter to a new pointer variable to be passed back onto the 
   parameter pointer argument */
static void * make_copy( SV* value, SV* length ){

    char * ptr;
    int len = SvIV( length );
    
    ptr = malloc( len + 1 );
    if ( ptr == NULL )
	return 0;
    memset(ptr, 0, len + 1);
    Copy(SvPV( value, len ), ptr, len, char);
    return ptr;

}


/* copy the value of a parameter to a new pointer variable to be passed back onto the 
   parameter pointer argument without the length supplied */
static void * make_strdup( SV* value ){

    char * ptr;
    int len = strlen(SvPV(value, PL_na));
    
    ptr = malloc( len + 1 );
    if ( ptr == NULL )
	return 0;
    memset(ptr, 0, len + 1);
    Copy(SvPV( value, len ), ptr, len, char);
    return ptr;

}

/* RfcAllow */
SV*  MyAllowStartProgram(SV* sv_program_name){
  
   RfcAllowStartProgram( SvPV(sv_program_name, PL_na) );
   return newSViv(1);
		    
}                                                                                                


/*
#define ENTRIES( tab ) ( sizeof(tab)/sizeof((tab)[0]) )
*/


/* build the RFC call interface, do the RFC call, and then build a complex
  hash structure of the results to pass back into perl */
SV* MyRfcCallReceive(SV* sv_handle, SV* sv_function, SV* iface){


   RFC_PARAMETER      myexports[MAX_PARA];
   RFC_PARAMETER      myimports[MAX_PARA];
   RFC_TABLE          mytables[MAX_PARA];
   RFC_RC             rc;
   RFC_HANDLE         handle;
   char *             function;
   char *             exception;
   RFC_ERROR_INFO_EX  error_info;
   /* RFC_ERROR_INFO     error_info; */

   int                tab_cnt, 
                      imp_cnt,
                      exp_cnt,
                      irow,
                      h_index,
                      a_index,
                      i,
                      j;

   AV*                array;
   HV*                h_parms;
   HV*                p_hash;
   HE*                h_entry;
   SV*                h_key;
   SV*                sv_type;

   HV*                hash = newHV();



/*
static RFC_TYPE_ELEMENT typeOfRfcTest[] =
{
  { "VINDX",    RFCTYPE_WSTRING,   8,    0 },
  { "VALUE",    RFCTYPE_WSTRING,       8,                 0 },

};

static RFC_TYPEHANDLE handleOfRfcTest;
*/




   tab_cnt = 0;
   exp_cnt = 0;
   imp_cnt = 0;

   handle = SvIV( sv_handle );
   function = SvPV( sv_function, PL_na );

   /* get the RFC interface definition hash  and iterate   */
   h_parms =  (HV*)SvRV( iface );
   h_index = hv_iterinit( h_parms );
   for (i = 0; i < h_index; i++) {

     /* grab each parameter hash */
       h_entry = hv_iternext( h_parms );
       h_key = hv_iterkeysv( h_entry );
       p_hash = (HV*)SvRV( hv_iterval(h_parms, h_entry) );
       sv_type = *hv_fetch( p_hash, (char *) "TYPE", 4, FALSE );

       /* determine the interface parameter type and build a definition */
       switch ( SvIV(sv_type) ){
	   case RFCIMPORT:
	     /* build an import parameter and allocate space for it to be returned into */
		 /*
		 if (strcmp("ZTEST", function) == 0)
		 {
             rc = RfcInstallStructure("RETURN",
                               typeOfRfcTest,
                               ENTRIES(typeOfRfcTest),
                               &handleOfRfcTest );
	   myimports[imp_cnt].name = make_strdup( h_key );
	   if ( myimports[imp_cnt].name == NULL )
	       return 0;
	   myimports[imp_cnt].nlen = strlen( SvPV(h_key, PL_na));
	   myimports[imp_cnt].addr = make_space( *hv_fetch(p_hash, (char *) "LEN", 3, FALSE) );
	   myimports[imp_cnt].leng = SvIV( *hv_fetch( p_hash, (char *) "LEN", 3, FALSE ) );
	   myimports[imp_cnt].type = handleOfRfcTest;
	   ++imp_cnt;
		 continue;
		 }
		 */
	   myimports[imp_cnt].name = make_strdup( h_key );
	   if ( myimports[imp_cnt].name == NULL )
	       return 0;
	   myimports[imp_cnt].nlen = strlen( SvPV(h_key, PL_na));
	   myimports[imp_cnt].addr = make_space( *hv_fetch(p_hash, (char *) "LEN", 3, FALSE) );
	   myimports[imp_cnt].leng = SvIV( *hv_fetch( p_hash, (char *) "LEN", 3, FALSE ) );
	   myimports[imp_cnt].type = SvIV( *hv_fetch( p_hash, (char *) "INTYPE", 6, FALSE ) );

	   ++imp_cnt;
	   break;

	   case RFCEXPORT:
	     /* build an export parameter and pass the value onto the structure */
	   myexports[exp_cnt].name = make_strdup( h_key );
	   if ( myexports[exp_cnt].name == NULL )
	       return 0;
	   myexports[exp_cnt].nlen = strlen( SvPV(h_key, PL_na));
	   myexports[exp_cnt].addr = make_copy( *hv_fetch(p_hash, (char *) "VALUE", 5, FALSE),
					        *hv_fetch(p_hash, (char *) "LEN", 3, FALSE) );
	   myexports[exp_cnt].leng = SvIV( *hv_fetch( p_hash, (char *) "LEN", 3, FALSE ) );
	   myexports[exp_cnt].type = SvIV( *hv_fetch( p_hash, (char *) "INTYPE", 6, FALSE ) );
	   ++exp_cnt;

	   break;

	   case RFCTABLE:
	     /* construct a table parameter and copy the table rows on to the table handle */
	   mytables[tab_cnt].name = make_strdup( h_key );
	   if ( mytables[tab_cnt].name == NULL )
	       return 0;
	   mytables[tab_cnt].nlen = strlen( SvPV(h_key, PL_na));
	   mytables[tab_cnt].leng = SvIV( *hv_fetch( p_hash, (char *) "LEN", 3, FALSE ) );
           mytables[tab_cnt].itmode = RFC_ITMODE_BYREFERENCE;
           mytables[tab_cnt].type = RFCTYPE_CHAR; 
	   /* maybe should be RFCTYPE_BYTE */
           mytables[tab_cnt].ithandle = 
	       ItCreate( mytables[tab_cnt].name,
			 SvIV( *hv_fetch( p_hash, (char *) "LEN", 3, FALSE ) ), 0 , 0 );
	   if ( mytables[tab_cnt].ithandle == NULL )
	       return 0; 

	   array = (AV*) SvRV( *hv_fetch( p_hash, (char *) "VALUE", 5, FALSE ) );
	   a_index = av_len( array );
	   for (j = 0; j <= a_index; j++) {
	       Copy(  SvPV( *av_fetch( array, j, FALSE ), PL_na ),
		      ItAppLine( mytables[tab_cnt].ithandle ),
		      mytables[tab_cnt].leng,
		      char );
	   };

	   tab_cnt++;

	   break;
	 default:
	   fprintf(stderr, "    I DONT KNOW WHAT THIS PARAMETER IS: %s \n", SvPV(h_key, PL_na));
           exit(0);
	   break;
       };

   };

   /* tack on a NULL value parameter to each type to signify that there are no more */
   myexports[exp_cnt].name = NULL;
   myexports[exp_cnt].nlen = 0;
   myexports[exp_cnt].leng = 0;
   myexports[exp_cnt].addr = NULL;
   myexports[exp_cnt].type = 0;

   myimports[imp_cnt].name = NULL;
   myimports[imp_cnt].nlen = 0;
   myimports[imp_cnt].leng = 0;
   myimports[imp_cnt].addr = NULL;
   myimports[imp_cnt].type = 0;

   mytables[tab_cnt].name = NULL;
   mytables[tab_cnt].ithandle = NULL;
   mytables[tab_cnt].nlen = 0;
   mytables[tab_cnt].leng = 0;
   mytables[tab_cnt].type = 0;


   /* do the actual RFC call to SAP */
   rc =  RfcCallReceive( handle, function,
				    myexports,
				    myimports,
				    mytables,
				    &exception );
  
   /* check the return code - if necessary construct an error message */
   if ( rc != RFC_OK ){
       RfcLastErrorEx( &error_info );
     if (( rc == RFC_EXCEPTION ) ||
         ( rc == RFC_SYS_EXCEPTION )) {
       hv_store(  hash, (char *) "__RETURN_CODE__", 15,
		  newSVpvf( "EXCEPT\t%s\tGROUP\t%d\tKEY\t%s\tMESSAGE\t%s", exception, error_info.group, error_info.key, error_info.message ),
		  0 );
     } else {
       hv_store(  hash, (char *) "__RETURN_CODE__", 15,
		  newSVpvf( "EXCEPT\t%s\tGROUP\t%d\tKEY\t%s\tMESSAGE\t%s","RfcCallReceive", error_info.group, error_info.key, error_info.message ),
		  0 );
     };
   } else {
       hv_store(  hash,  (char *) "__RETURN_CODE__", 15, newSVpvf( "%d", RFC_OK ), 0 );
   };

   /*
   if ( rc != RFC_OK ){
       RfcLastError( &error_info );
     if (( rc == RFC_EXCEPTION ) ||
         ( rc == RFC_SYS_EXCEPTION )) {
       hv_store(  hash, (char *) "__RETURN_CODE__", 15,
		  newSVpvf( "EXCEPT\t%s\tKEY\t%s\tSTATUS\t%s\tMESSAGE\t%sINTSTAT\t%s", exception, error_info.key, error_info.status, error_info.message, error_info.intstat ),
		  0 );
     } else {
       hv_store(  hash, (char *) "__RETURN_CODE__", 15,
		  newSVpvf( "EXCEPT\t%s\tKEY\t%s\tSTATUS\t%s\tMESSAGE\t%sINTSTAT\t%s", exception, error_info.key, error_info.status, error_info.message, error_info.intstat ),
		  0 );
     };
   } else {
       hv_store(  hash,  (char *) "__RETURN_CODE__", 15, newSVpvf( "%d", RFC_OK ), 0 );
   };
   */


   /* free up the used memory for export parameters */
   for (exp_cnt = 0; exp_cnt < MAX_PARA; exp_cnt++){
       if ( myexports[exp_cnt].name == NULL ){
	   break;
       } else {
	   free(myexports[exp_cnt].name);
       };
       myexports[exp_cnt].name = NULL;
       myexports[exp_cnt].nlen = 0;
       myexports[exp_cnt].leng = 0;
       myexports[exp_cnt].type = 0;
       if ( myexports[exp_cnt].addr != NULL ){
	   free(myexports[exp_cnt].addr);
       };
       myexports[exp_cnt].addr = NULL;
   };

   
   /* retrieve the values of the import parameters and free up the memory */
   for (imp_cnt = 0; imp_cnt < MAX_PARA; imp_cnt++){
       if ( myimports[imp_cnt].name == NULL ){
	   break;
       };
       if ( myimports[imp_cnt].name != NULL ){
         switch ( myimports[imp_cnt].type ){
/*	 case RFCTYPE_INT:
	 case RFCTYPE_FLOAT:    */
	 default:
	   /*  All the other SAP internal data types
	       case RFCTYPE_CHAR:
	       case RFCTYPE_BYTE:
	       case RFCTYPE_NUM:
	       case RFCTYPE_BCD:
	       case RFCTYPE_DATE:
	       case RFCTYPE_TIME: */
	   hv_store(  hash, myimports[imp_cnt].name, myimports[imp_cnt].nlen, newSVpv( myimports[imp_cnt].addr, myimports[imp_cnt].leng ), 0 );
	   break;
	 };
         free(myimports[imp_cnt].name);
       };
       myimports[imp_cnt].name = NULL;
       myimports[imp_cnt].nlen = 0;
       myimports[imp_cnt].leng = 0;
       myimports[imp_cnt].type = 0;
       if ( myimports[imp_cnt].addr != NULL ){
	   free(myimports[imp_cnt].addr);
       };
       myimports[imp_cnt].addr = NULL;

   };
   
   /* retrieve the values of the table parameters and free up the memory */
   for (tab_cnt = 0; tab_cnt < MAX_PARA; tab_cnt++){
       if ( mytables[tab_cnt].name == NULL ){
	   break;
       };
       if ( mytables[tab_cnt].name != NULL ){
#ifdef DOIBMWKRND
	   hv_store(  hash, mytables[tab_cnt].name, mytables[tab_cnt].nlen, newRV_noinc( array = newAV() ), 0);
#else
	   hv_store(  hash, mytables[tab_cnt].name, mytables[tab_cnt].nlen, newRV_noinc( (SV*) ( array = newAV() ) ), 0);
#endif
	   /*  grab each table row and push onto an array */
	   for (irow = 1; irow <=  ItFill(mytables[tab_cnt].ithandle); irow++){
	       av_push( array, newSVpv( ItGetLine( mytables[tab_cnt].ithandle, irow ), mytables[tab_cnt].leng ) );
	   };
	   
	   free(mytables[tab_cnt].name);
       };
       mytables[tab_cnt].name = NULL;
       if ( mytables[tab_cnt].ithandle != NULL ){
	   ItFree( mytables[tab_cnt].ithandle );
       };
       mytables[tab_cnt].ithandle = NULL;
       mytables[tab_cnt].nlen = 0;
       mytables[tab_cnt].leng = 0;
       mytables[tab_cnt].type = 0;

   };
   
   return newRV_noinc( (SV*) hash);

}


RFC_RC loop_callback(SV* sv_callback_handler, SV* sv_self)
{

    int result;
    SV* sv_rvalue;
    dSP;

    /* if there is no handler then get out of here */
    if (! SvTRUE(sv_callback_handler))
      return RFC_OK;

    /* initialising the argument stack */
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);

    /* push the pkt onto the stack */
    XPUSHs( sv_self );

    /* stash the stack point */
    PUTBACK;

    result = perl_call_sv(sv_callback_handler, G_EVAL | G_SCALAR );

    /* disassemble the results off the argument stack */
    if(SvTRUE(ERRSV))
        fprintf(stderr, "RFC callback - perl call errored: %s\n", SvPV(ERRSV,PL_na));
    SPAGAIN;

    /* was this handled or passed? */
    /* fprintf(stderr, "results are: %d \n", result); */
    if (result > 0){
      sv_rvalue = newSVsv(POPs);
    } else {
      sv_rvalue = newSViv(0);
    }
    PUTBACK;
    FREETMPS;
    LEAVE;

    if (SvTRUE(sv_rvalue)){
      return RFC_OK;
    } else {
      return RFC_SYS_EXCEPTION;
    }

}



/*--------------------------------------------------------------------*/
/* TID_CHECK-Function for transactional RFC                           */
/*--------------------------------------------------------------------*/
static int DLL_CALL_BACK_FUNCTION TID_check(RFC_TID tid)
{
    /* fprintf(stderr, "\n\nStart Function TID_CHECK      TID = %s\n", tid); */

    int result;
    SV* sv_callback_handler;
    SV* sv_rvalue;
    dSP;

    sv_callback_handler = (SV*) *hv_fetch(p_saprfc, (char *) "TRFC_CHECK", 10, FALSE); 
    /* if there is no handler then get out of here */
    if (! SvTRUE(sv_callback_handler))
      return 0;

    /* initialising the argument stack */
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);

    /* push the tid onto the stack */
    XPUSHs( newSVpvf("%s",tid) );

    /* stash the stack point */
    PUTBACK;

    result = perl_call_sv(sv_callback_handler, G_EVAL | G_SCALAR );

    /* disassemble the results off the argument stack */
    if(SvTRUE(ERRSV))
        fprintf(stderr, "RFC TID_check callback - perl call errored: %s\n", SvPV(ERRSV,PL_na));
    SPAGAIN;

    /* was this handled or passed? */
    if (result > 0){
      sv_rvalue = newSVsv(POPs);
    } else {
      sv_rvalue = newSViv(0);
    }
    PUTBACK;
    FREETMPS;
    LEAVE;

    if (SvTRUE(sv_rvalue)){
      memset(current_tid, 0, sizeof(current_tid));
      return 1;
    } else {
      sprintf(current_tid+0, "%s", tid);
      return 0;
    }

}


/*--------------------------------------------------------------------*/
/* TID_COMMIT-Function for transactional RFC                          */
/*--------------------------------------------------------------------*/
static void DLL_CALL_BACK_FUNCTION TID_commit(RFC_TID tid)
{
    /* fprintf(stderr, "\n\nStart Function TID_COMMIT     TID = %s\n", tid); */

    int result;
    SV* sv_callback_handler;
    dSP;

    sv_callback_handler = (SV*) *hv_fetch(p_saprfc, (char *) "TRFC_COMMIT", 11, FALSE); 
    /* if there is no handler then get out of here */
    if (! SvTRUE(sv_callback_handler))
      return;

    /* initialising the argument stack */
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);

    /* push the tid onto the stack */
    XPUSHs( newSVpvf("%s",tid) );

    /* stash the stack point */
    PUTBACK;

    result = perl_call_sv(sv_callback_handler, G_EVAL | G_DISCARD );

    /* disassemble the results off the argument stack */
    if(SvTRUE(ERRSV))
        fprintf(stderr, "RFC TID_commit callback - perl call errored: %s\n", SvPV(ERRSV,PL_na));
    SPAGAIN;
    PUTBACK;
    FREETMPS;
    LEAVE;

    return;
}


/*--------------------------------------------------------------------*/
/* CONFIRM-Function for transactional RFC                             */
/*--------------------------------------------------------------------*/
static void DLL_CALL_BACK_FUNCTION TID_confirm(RFC_TID tid)
{
    /* fprintf(stderr, "\n\nStart Function TID_CONFIRM    TID = %s\n", tid); */

    int result;
    SV* sv_callback_handler;
    dSP;

    sv_callback_handler = (SV*) *hv_fetch(p_saprfc, (char *) "TRFC_CONFIRM", 12, FALSE); 
    /* if there is no handler then get out of here */
    if (! SvTRUE(sv_callback_handler))
      return;

    /* initialising the argument stack */
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);

    /* push the tid onto the stack */
    XPUSHs( newSVpvf("%s",tid) );

    /* stash the stack point */
    PUTBACK;

    result = perl_call_sv(sv_callback_handler, G_EVAL | G_DISCARD );

    /* disassemble the results off the argument stack */
    if(SvTRUE(ERRSV))
        fprintf(stderr, "RFC TID_confirm callback - perl call errored: %s\n", SvPV(ERRSV,PL_na));
    SPAGAIN;
    PUTBACK;
    FREETMPS;
    LEAVE;

    return;
}


/*--------------------------------------------------------------------*/
/* TID_ROLLBACK-Function for transactional RFC                        */
/*--------------------------------------------------------------------*/
static void DLL_CALL_BACK_FUNCTION TID_rollback(RFC_TID tid)
{
    /* fprintf(stderr, "\n\nStart Function TID_ROLLBACK   TID = %s\n", tid); */

    int result;
    SV* sv_callback_handler;
    dSP;

    sv_callback_handler = (SV*) *hv_fetch(p_saprfc, (char *) "TRFC_ROLLBACK", 13, FALSE); 
    /* if there is no handler then get out of here */
    if (! SvTRUE(sv_callback_handler))
      return;

    /* initialising the argument stack */
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);

    /* push the tid onto the stack */
    XPUSHs( newSVpvf("%s",tid) );

    /* stash the stack point */
    PUTBACK;

    result = perl_call_sv(sv_callback_handler, G_EVAL | G_DISCARD );

    /* disassemble the results off the argument stack */
    if(SvTRUE(ERRSV))
        fprintf(stderr, "RFC TID_rollback callback - perl call errored: %s\n", SvPV(ERRSV,PL_na));
    SPAGAIN;
    PUTBACK;
    FREETMPS;
    LEAVE;

    return;
}


static RFC_RC DLL_CALL_BACK_FUNCTION user_global_server(RFC_HANDLE handle)
{

  RFC_RC rc;
  RFC_FUNCTIONNAME  funcname;
  SV* sv_iface;

  rc = RfcGetName(handle, funcname);
  if (rc != RFC_OK)
  {
     /* fprintf(stderr, "RFC connection failure code: %d \n", rc); */
     /* hv_store(p_saprfc, (char *) "ERROR", 5, newSVpvf("RFC connection failure code: %d", rc), 0); */
       return rc;
  }

  /* check at this point for registered functions */
  if ( ! hv_exists(p_iface_hash, funcname, strlen(funcname)) ){
       fprintf(stderr, "the MISSING Function Name is: %s\n", funcname);
       RfcRaise( handle, "FUNCTION_MISSING" );
       /* do event callback to intertwine other events */
       /* rc = loop_callback(sv_callback, sv_saprfc); */
       /* XXX   */
       return RFC_NOT_FOUND;
  }

  /* pass in the interface to be handled */
  sv_iface = *hv_fetch(p_iface_hash, funcname, strlen(funcname), FALSE);

  handle_request(handle, sv_iface);

  rc = loop_callback(sv_callback, global_saprfc);

  return rc;
}

#undef  NL
#define NL "\n"

static char *user_global_server_docu(void)
{
  static char docu[] =
  "The RFC library will call this function if any unknown"            NL
  "RFC function should be executed in this RFC server program."       NL
    ;
  return docu;
}


SV* my_accept( SV* sv_conn, SV* sv_docu, SV* sv_ifaces, SV* sv_saprfc )
{
   /* initialized data */
   static RFC_ENV    env;
   RFC_ERROR_INFO_EX  error_info;
   RFC_HANDLE handle;
   RFC_RC     rc;
   RFC_FUNCTIONNAME funcname;
   SV* sv_iface;
   SV* sv_wait;
   SV* sv_is_trfc;
   RFC_INT wtime = 0; 
   RFC_INT ntotal,
           ninit,
           nready,
           nbusy;
   char   gwserv[8];

   /*
    * install error handler
    */
   memset(current_tid, 0, sizeof(current_tid));
   global_saprfc = sv_saprfc;
   p_saprfc = (HV*)SvRV( sv_saprfc );

   env.errorhandler = rfc_error;
   RfcEnvironment( &env );

   /*
    * accept connection
    *
    * (command line argv must be passed to RfcAccept)
    */
   /* fprintf(stderr, "The connection string is: %s\n", SvPV(sv_conn, SvCUR(sv_conn))); */

   /* get the tRFC indicator  */
   sv_is_trfc = (SV*) *hv_fetch(p_saprfc, (char *) "TRFC", 4, FALSE); 

   handle = RfcAcceptExt( SvPV(sv_conn, SvCUR(sv_conn)) );

   /* fprintf(stderr, "what is my handle: %d\n", handle); */
   sprintf(gwserv, "%d", SvIV((SV*) *hv_fetch(p_saprfc, (char *) "GWSERV", 6, FALSE))); 
   rc = RfcCheckRegisterServer( SvPV((SV*) *hv_fetch(p_saprfc, (char *) "TPNAME", 6, FALSE), PL_na),
                                SvPV((SV*) *hv_fetch(p_saprfc, (char *) "GWHOST", 6, FALSE), PL_na), 
 			        gwserv, 
 			        &ntotal, &ninit, &nready, &nbusy, &error_info);

   if (rc != RFC_OK)
   {
     /*
     fprintf(stderr, "\nGroup       Error group %d\n", error_info.group);
     fprintf(stderr, "Key         %s\n", error_info.key);
     fprintf(stderr, "Message     %s\n\n", error_info.message);
     */
     hv_store(p_saprfc, (char *) "ERROR", 5, 
        newSVpvf("\nGroup       Error group %d\nKey         %s\nMessage     %s\n\n", 
	           error_info.group, error_info.key, error_info.message), 0);
     return newSViv(-1);
   }

   /* obscure error when SAP is starting up but still get RFC_OK above */
   if (ntotal == 0)
   {
     hv_store(p_saprfc, (char *) "ERROR", 5, 
        newSVpvf("\nGroup       Error group 102\nKey         RFC_ERROR_COMMUNICATION\nMessage     Error connecting to the gateway - no registered servers found\n\n"), 0);
     return newSViv(-1);
   }
   /*
   fprintf(stderr, "\nNo. registered servers               :  %d", ntotal);
   fprintf(stderr, "\nNo. registered servers in INIT-state :  %d", ninit);
   fprintf(stderr, "\nNo. registered servers in READY-state:  %d", nready);
   fprintf(stderr, "\nNo. registered servers in BUSY-state :  %d", nbusy);
   */


   if (SvTRUE(sv_is_trfc)) {
   /* Install transaction control   */
     RfcInstallTransactionControl((RFC_ON_CHECK_TID)   TID_check,
                                  (RFC_ON_COMMIT)      TID_commit,
                                  (RFC_ON_ROLLBACK)    TID_rollback,
                                  (RFC_ON_CONFIRM_TID) TID_confirm);
   }

   /*
    * static function to install offered function modules - RFC_DOCU
    */
   sv_store_docu = sv_docu;

   rc = install_docu(handle);

   if( rc != RFC_OK )
   {
     RfcAbort( handle, "Initialisation error" );
     hv_store(p_saprfc, (char *) "ERROR", 5, newSVpvf("Initialisation error in the gateway"), 0);
     return newSViv(-1);
   }

   p_iface_hash = (HV*)SvRV( sv_ifaces );

#ifdef SAPonNT
   /* if one uses rfcexec as a bootstrap to start the
    * RFC COM support features, one need to initialize
    * Win32's COM routines
    * we discared the return value since there are few
    * users for this scenario. If this call fails the
    * follwing COM calls will break anyway, so that users
    * which do need this call will not go far.
    * for users, which do not need this call,
    * it would be unfortunate to stop here
    */
    /*
    Remove this temporarily to fix compiler problems for WIN32
   (void)CoInitialize(NULL);
   */
#endif

   /*
    *  Setup the wait value
    *
    */
    sv_callback = *hv_fetch(p_saprfc, (char *) "CALLBACK", 8, FALSE);
    sv_wait = *hv_fetch(p_saprfc, (char *) "WAIT", 4, FALSE);
    if (SvTRUE(sv_wait))
       wtime = SvIV(sv_wait);
    else
       wtime = RFC_WAIT_TIME;
   

    /* global handler for tRFC  */
    if (SvTRUE(sv_is_trfc)) {
        rc = RfcInstallFunction(name_user_global_server,
                             (RFC_ONCALL) user_global_server,
	                      user_global_server_docu());
       if( rc != RFC_OK )
       {
           fprintf(stderr, "\nERROR: Install %s     rfc_rc = %d",
	                   name_user_global_server, rc);
           RfcAbort( handle, "Cant install global tRFC handler" );
           return newSViv(-1);
       }
    }

   
    /* fprintf(stderr, "The Wait time is: %d \n", wtime); */

   /*
    * enter main loop
    */
   do
   {
     /* fprintf(stderr, "going to wait ...\n");  */
     rc = RfcWaitForRequest(handle, wtime);
     /* fprintf(stderr, "done the wait: %d \n", rc);  */

     /* needs to get an RFC_OK or RFC_RETRY */
     if (rc == RFC_RETRY){
       /*  do event loop callback here for interloop breakout */
       /* fprintf(stderr, "got into the retry...\n"); */
       rc = loop_callback(sv_callback, sv_saprfc);
       continue;
     }

     /* short circuit here for tRFC  */
     if (SvTRUE(sv_is_trfc)) {
         rc = RfcDispatch(handle);
         /* fprintf(stderr, "done the dispatch: %d \n", rc);  */
         continue;
     }

     /* this will block until a straight RFC call is made */
     if (rc == RFC_OK)
       rc = RfcGetName(handle, funcname);

     if (rc != RFC_OK){
       /* fprintf(stderr, "RFC connection failure code: %d \n", rc); */
       hv_store(p_saprfc, (char *) "ERROR", 5, newSVpvf("RFC connection failure code: %d", rc), 0);
       continue;
     }

     /* check at this point for registered functions */
     if ( ! hv_exists(p_iface_hash, funcname, strlen(funcname)) ){
       fprintf(stderr, "the MISSING Function Name is: %s\n", funcname);
       RfcRaise( handle, "FUNCTION_MISSING" );
       /* do event callback to intertwine other events */
       rc = loop_callback(sv_callback, sv_saprfc);
       continue;
     }

     /* pass in the interface to be handled */
     sv_iface = *hv_fetch(p_iface_hash, funcname, strlen(funcname), FALSE);

     handle_request(handle, sv_iface);

     /* fprintf(stderr, "round the loop ...\n"); */

     /* do event callback to intertwine other events */
     rc = loop_callback(sv_callback, sv_saprfc);

   } while( rc == RFC_OK || rc == RFC_RETRY );

   /*
    * connection was closed by the client :
    * also close connection and terminate
    */
   RfcClose( handle );

#ifdef SAPonNT
    /*
    Remove this temporarily to fix compiler problems for WIN32
   (void)CoUninitialize();
   */
#endif

   return newSViv(rc);
} /* main */



static RFC_RC install_docu( RFC_HANDLE handle )
{
   RFC_RC rc;

   /*
    * install the function modules offered
    *
    * the documentation texts are placed in static memory
    * within some static functions to keep things readable.
    */

   /*
    * RFC_DOCU interface
    */
   rc = RfcInstallFunction("RFC_DOCU",
			    do_docu,
			    do_docu_docu() );
   if( rc != RFC_OK ) return rc;

   return RFC_OK;
} /* install_docu */


/*====================================================================*/
/*                                                                    */
/* Get specific info about an RFC connection                          */
/*                                                                    */
/*====================================================================*/
void get_attributes(RFC_HANDLE rfc_handle, HV* hv_sysinfo)
{
  RFC_ATTRIBUTES    rfc_attributes;
  RFC_RC rc;

  hv_clear(hv_sysinfo);

  rc = RfcGetAttributes(rfc_handle, &rfc_attributes);
  if (rc != RFC_OK)
    return;

  hv_store(hv_sysinfo, "dest", 4, newSVpv(rfc_attributes.dest, strlen(rfc_attributes.dest)), 0);
  hv_store(hv_sysinfo, "localhost", 9, newSVpv(rfc_attributes.own_host, strlen(rfc_attributes.own_host)), 0);
  if (rfc_attributes.rfc_role == RFC_ROLE_CLIENT)
  {
    if (rfc_attributes.partner_type == RFC_SERVER_EXT)
      hv_store(hv_sysinfo, "servprogname", 12, newSVpv(rfc_attributes.partner_host, strlen(rfc_attributes.partner_host)), 0);
    else if (rfc_attributes.partner_type == RFC_SERVER_EXT_REG)
      hv_store(hv_sysinfo, "servprogid", 10, newSVpv(rfc_attributes.partner_host, strlen(rfc_attributes.partner_host)), 0);
    else
      hv_store(hv_sysinfo, "partnerhost", 11, newSVpv(rfc_attributes.partner_host, strlen(rfc_attributes.partner_host)), 0);
  }
  else
    hv_store(hv_sysinfo, "partnerhost", 11, newSVpv(rfc_attributes.partner_host, strlen(rfc_attributes.partner_host)), 0);

  hv_store(hv_sysinfo, "sysnr", 5, newSVpv(rfc_attributes.systnr, strlen(rfc_attributes.systnr)), 0);
  hv_store(hv_sysinfo, "sysid", 5, newSVpv(rfc_attributes.sysid, strlen(rfc_attributes.sysid)), 0);
  hv_store(hv_sysinfo, "mandt", 5, newSVpv(rfc_attributes.client, strlen(rfc_attributes.client)), 0);
  hv_store(hv_sysinfo, "user", 4, newSVpv(rfc_attributes.user, strlen(rfc_attributes.user)), 0);
  hv_store(hv_sysinfo, "lang", 4, newSVpv(rfc_attributes.language, strlen(rfc_attributes.language)), 0);
  hv_store(hv_sysinfo, "isolang", 7, newSVpv(rfc_attributes.ISO_language, strlen(rfc_attributes.ISO_language)), 0);
  if (rfc_attributes.trace == 'X')
       hv_store(hv_sysinfo, "trace", 5, newSVpv("ON", 2), 0);
  else
       hv_store(hv_sysinfo, "trace", 5, newSVpv("OFF", 3), 0);

  hv_store(hv_sysinfo, "localcodepage", 13, newSVpv(rfc_attributes.own_codepage, strlen(rfc_attributes.own_codepage)), 0);
  hv_store(hv_sysinfo, "partnercodepage", 15, newSVpv(rfc_attributes.partner_codepage, strlen(rfc_attributes.partner_codepage)), 0);
  if (rfc_attributes.rfc_role == RFC_ROLE_CLIENT)
    hv_store(hv_sysinfo, "rfcrole", 7, newSVpv("External RFC Client", strlen("External RFC Client")), 0);
  else if (rfc_attributes.own_type == RFC_SERVER_EXT)
    hv_store(hv_sysinfo, "rfcrole", 7, newSVpv("External RFC Server, started by SAP gateway", strlen("External RFC Server, started by SAP gateway")), 0);
  else
    hv_store(hv_sysinfo, "rfcrole", 7, newSVpv("External RFC Server, registered at SAP gateway", strlen("External RFC Server, registered at SAP gateway")), 0);

  hv_store(hv_sysinfo, "rel", 3, newSVpv(rfc_attributes.own_rel, strlen(rfc_attributes.own_rel)), 0);

  if (rfc_attributes.partner_type == RFC_SERVER_R3)
    hv_store(hv_sysinfo, "rfcpartner", 10, newSVpv("R3", strlen("R3")), 0);
  else if (rfc_attributes.partner_type == RFC_SERVER_R2)
    hv_store(hv_sysinfo, "rfcpartner", 10, newSVpv("R2", strlen("R2")), 0);
  else if (rfc_attributes.rfc_role == RFC_ROLE_CLIENT)
  {
    if (rfc_attributes.partner_type == RFC_SERVER_EXT)
      hv_store(hv_sysinfo, "rfcpartner", 10, newSVpv("External RFC Server, started by SAP gateway", strlen("External RFC Server, started by SAP gateway")), 0);
    else
      hv_store(hv_sysinfo, "rfcpartner", 10, newSVpv("External RFC Server, registered at SAP gateway", strlen("External RFC Server, registered at SAP gateway")), 0);
  }
  else
    hv_store(hv_sysinfo, "rfcpartner", 10, newSVpv("External RFC Client", strlen("External RFC Client")), 0);

  hv_store(hv_sysinfo, "partnerrel", 10, newSVpv(rfc_attributes.partner_rel, strlen(rfc_attributes.partner_rel)), 0);
  hv_store(hv_sysinfo, "kernelrel", 9, newSVpv(rfc_attributes.kernel_rel, strlen(rfc_attributes.kernel_rel)), 0);
  hv_store(hv_sysinfo, "convid", 6, newSVpv(rfc_attributes.CPIC_convid, strlen(rfc_attributes.CPIC_convid)), 0);

  return;
}


/*
 * Generic Inbound RFC Request Handler
 *
 */
static RFC_RC DLL_CALL_BACK_FUNCTION handle_request(  RFC_HANDLE handle, SV* sv_iface )
{
    char          command[256];
    RFC_PARAMETER parameter[MAX_PARA];
    RFC_TABLE     table[MAX_PARA];
    RFC_RC        rc;
    RFC_CHAR      read_flag = 0;
    int           mode;
    char * p;
    char ** exception;
    int           tab_cnt, 
                  imp_cnt,
                  exp_cnt,
                  irow,
                  h_index,
                  a_index,
                  i,
                  j;

    AV*           array;
    HV*           h_parms;
    HV*           p_hash;
    HV*           hv_sysinfo;
    HE*           h_entry;
    SV*           h_key;
    SV*           sv_type;
    SV*           sv_result;
    SV*           sv_callback_handler;
    SV*           sv_self;

    HV*           hash = newHV();

    tab_cnt = 0;
    exp_cnt = 0;
    imp_cnt = 0;
 
    /* get the RFC interface definition hash  and iterate   */
    h_parms =  (HV*)SvRV( sv_iface );
    h_index = hv_iterinit( h_parms );

    for (i = 0; i < h_index; i++) {
       /* grab each parameter hash */
       h_entry = hv_iternext( h_parms );
       h_key = hv_iterkeysv( h_entry );
       /* fprintf(stderr, "processing parameter: %s\n", SvPV(h_key, PL_na));  */
       if (strncmp("__HANDLER__", SvPV(h_key, PL_na),11) == 0 ||
           strncmp("__SELF__", SvPV(h_key, PL_na),8) == 0){
	  continue;
       }

       /* fprintf(stderr, "ok want this parameter ...\n"); */
       p_hash = (HV*)SvRV( hv_iterval(h_parms, h_entry) );
       sv_type = *hv_fetch( p_hash, (char *) "TYPE", 4, FALSE );

       /* determine the interface parameter type and build a definition */
       switch ( SvIV(sv_type) ){
	   case RFCIMPORT:
	     /* build an import parameter and allocate space for it to be returned into */
           /* fprintf(stderr, "adding import parameter name is: %s\n", SvPV(h_key, PL_na)); */
	   parameter[imp_cnt].name = make_strdup( h_key );
	   if ( parameter[imp_cnt].name == NULL )
	       return 0;
	   parameter[imp_cnt].nlen = strlen( SvPV(h_key, PL_na));
	   parameter[imp_cnt].addr = make_space( *hv_fetch(p_hash, (char *) "LEN", 3, FALSE) );
	   parameter[imp_cnt].leng = SvIV( *hv_fetch( p_hash, (char *) "LEN", 3, FALSE ) );
	   parameter[imp_cnt].type = SvIV( *hv_fetch( p_hash, (char *) "INTYPE", 6, FALSE ) );
	   ++imp_cnt;
	   break;

	   case RFCTABLE:
	     /* construct a table parameter and copy the table rows on to the table handle */
           /* fprintf(stderr, "adding table parameter name is: %s\n", SvPV(h_key, PL_na)); */
	   table[tab_cnt].name = make_strdup( h_key );
	   if ( table[tab_cnt].name == NULL )
	       return 0;
	   table[tab_cnt].nlen = strlen( SvPV(h_key, PL_na));
	   table[tab_cnt].leng = SvIV( *hv_fetch( p_hash, (char *) "LEN", 3, FALSE ) );
           table[tab_cnt].itmode = RFC_ITMODE_BYREFERENCE;
           table[tab_cnt].type = RFCTYPE_CHAR; 
	   /* maybe should be RFCTYPE_BYTE */
	   tab_cnt++;
	   break;
	 default:
	   /* ignore export parameters */
	   break;
       };

    };

    /* tack on a NULL value parameter to each type to signify that there are no more */
    parameter[imp_cnt].name = NULL;
    parameter[imp_cnt].nlen = 0;
    parameter[imp_cnt].leng = 0;
    parameter[imp_cnt].addr = NULL;
    parameter[imp_cnt].type = 0;

    table[tab_cnt].name = NULL;
    table[tab_cnt].ithandle = NULL;
    table[tab_cnt].nlen = 0;
    table[tab_cnt].leng = 0;
    table[tab_cnt].type = 0;

    /* fprintf(stderr, "going to import parameter data...\n"); */
    rc = RfcGetData( handle, parameter, table );

    /* fprintf(stderr, "return code: %d\n", rc); */
    if( rc != RFC_OK ) return rc;

    for (imp_cnt = 0; imp_cnt < MAX_PARA; imp_cnt++){
       if ( parameter[imp_cnt].name == NULL ){
	   break;
       };
       /* fprintf(stderr, "getting import parameter: %s \n", parameter[imp_cnt].name); */
       if ( parameter[imp_cnt].name != NULL ){
	 hv_store(  hash, parameter[imp_cnt].name, parameter[imp_cnt].nlen, newSVpv( parameter[imp_cnt].addr, parameter[imp_cnt].leng ), 0 );
         free(parameter[imp_cnt].name);
       };
       /* fprintf(stderr, " parameter value: %s \n", parameter[imp_cnt].addr); */
       parameter[imp_cnt].name = NULL;
       parameter[imp_cnt].nlen = 0;
       parameter[imp_cnt].leng = 0;
       parameter[imp_cnt].type = 0;
       if ( parameter[imp_cnt].addr != NULL ){
	   free(parameter[imp_cnt].addr);
       };
       parameter[imp_cnt].addr = NULL;

    };
   
    /* retrieve the values of the table parameters and free up the memory */
    for (tab_cnt = 0; tab_cnt < MAX_PARA; tab_cnt++){
       if ( table[tab_cnt].name == NULL ){
	   break;
       };
       /* fprintf(stderr, "getting table parameter: %s \n", table[tab_cnt].name); */
       if ( table[tab_cnt].name != NULL ){
#ifdef DOIBMWKRND
	   hv_store(  hash, table[tab_cnt].name, table[tab_cnt].nlen, newRV_noinc( array = newAV() ), 0);
#else
	   hv_store(  hash, table[tab_cnt].name, table[tab_cnt].nlen, newRV_noinc( (SV*) ( array = newAV() ) ), 0);
#endif
	   /*  grab each table row and push onto an array */
	   if (table[tab_cnt].ithandle != NULL){
	      /* fprintf(stderr, "going to check count\n");
	      fprintf(stderr, "the table count is: %d \n", ItFill(table[tab_cnt].ithandle)); */
	      for (irow = 1; irow <=  ItFill(table[tab_cnt].ithandle); irow++){
	          av_push( array, newSVpv( ItGetLine( table[tab_cnt].ithandle, irow ), table[tab_cnt].leng ) );
	      };
	   };
	   
	   free(table[tab_cnt].name);
       };
       table[tab_cnt].name = NULL;
       if ( table[tab_cnt].ithandle != NULL ){
	   ItFree( table[tab_cnt].ithandle );
       };
       table[tab_cnt].ithandle = NULL;
       table[tab_cnt].nlen = 0;
       table[tab_cnt].leng = 0;
       table[tab_cnt].type = 0;

    };


    /* fprintf(stderr, "got data - now do callback\n"); */
    sv_callback_handler = *hv_fetch(h_parms, (char *) "__HANDLER__", 11, FALSE);
    sv_self = *hv_fetch(h_parms, (char *) "__SELF__", 8, FALSE);

    /* get the systeminfo of the current connection */
    hv_sysinfo = (HV*)SvRV(*hv_fetch((HV*)SvRV(sv_self),  (char *) "SYSINFO", 7, FALSE));
    get_attributes(handle, hv_sysinfo);

    sv_result = call_handler( sv_callback_handler, sv_self, newRV_noinc( (SV*) hash) );

    /* if( rc != RFC_OK ) return rc; */

    /* fprintf(stderr, "Result is: %s \n", SvPV(sv_result, PL_na)); */

    /* get the RFC interface definition hash  and iterate   */
    h_parms =  (HV*)SvRV( sv_result );
    h_index = hv_iterinit( h_parms );

    /* fprintf(stderr, "processing parameters: %d ...\n", h_index); */
    exp_cnt = 0;
    tab_cnt = 0;
    for (i = 0; i < h_index; i++) {
       /* grab each parameter hash */
       h_entry = hv_iternext( h_parms );
       h_key = hv_iterkeysv( h_entry );

       /*  Check for a serious error */
       if (strncmp("__EXCEPTION__", SvPV(h_key, PL_na),13) == 0){
          sv_type  = (SV*) hv_iterval(h_parms, h_entry);
	  /* fprintf(stderr, "Got an exception: %s \n", SvPV(sv_type, PL_na)); */
          RfcRaise( handle, SvPV(sv_type, PL_na) );
	  return 0;
       }

       /* fprintf(stderr, "processing parameter: %s\n", SvPV(h_key, PL_na)); */
       if (strncmp("__HANDLER__", SvPV(h_key, PL_na),11) == 0 ||
           strncmp("__SELF__", SvPV(h_key, PL_na),8) == 0){
          /* fprintf(stderr, "dont want the handler...\n"); */
	  continue;
       }
       /* fprintf(stderr, "ok want this parameter ...\n"); */
       p_hash = (HV*)SvRV( hv_iterval(h_parms, h_entry) );
       sv_type = *hv_fetch( p_hash, (char *) "TYPE", 4, FALSE );

       /* determine the interface parameter type and build a definition */
       switch ( SvIV(sv_type) ){
	   case RFCEXPORT:
	     /* build an export parameter and pass the value onto the structure */
	   parameter[exp_cnt].name = make_strdup( h_key );
	   if ( parameter[exp_cnt].name == NULL )
	       return 0;
	   parameter[exp_cnt].nlen = strlen( SvPV(h_key, PL_na));
	   parameter[exp_cnt].addr = make_copy( *hv_fetch(p_hash, (char *) "VALUE", 5, FALSE),
					        *hv_fetch(p_hash, (char *) "LEN", 3, FALSE) );
	   parameter[exp_cnt].leng = SvIV( *hv_fetch( p_hash, (char *) "LEN", 3, FALSE ) );
	   parameter[exp_cnt].type = SvIV( *hv_fetch( p_hash, (char *) "INTYPE", 6, FALSE ) );
	   ++exp_cnt;

	   break;

	   case RFCTABLE:
	     /* construct a table parameter and copy the table rows on to the table handle */
           /* fprintf(stderr, "adding table parameter name is: %s\n", SvPV(h_key, PL_na)); */
	   table[tab_cnt].name = make_strdup( h_key );
	   if ( table[tab_cnt].name == NULL )
	       return 0;
	   table[tab_cnt].nlen = strlen( SvPV(h_key, PL_na));
	   table[tab_cnt].leng = SvIV( *hv_fetch( p_hash, (char *) "LEN", 3, FALSE ) );
           table[tab_cnt].itmode = RFC_ITMODE_BYREFERENCE;
           table[tab_cnt].type = RFCTYPE_CHAR; 
	   /* maybe should be RFCTYPE_BYTE */
           table[tab_cnt].ithandle = 
	       ItCreate( table[tab_cnt].name,
			 SvIV( *hv_fetch( p_hash, (char *) "LEN", 3, FALSE ) ), 0 , 0 );
	   if ( table[tab_cnt].ithandle == NULL )
	       return 0; 

	   array = (AV*) SvRV( *hv_fetch( p_hash, (char *) "VALUE", 5, FALSE ) );
	   a_index = av_len( array );
	   /* fprintf(stderr, "the array contains: %d \n", a_index); */
	   /* fprintf(stderr, "the array id is: %d \n", tab_cnt); */
	   for (j = 0; j <= a_index; j++) {
	       Copy(  SvPV( *av_fetch( array, j, FALSE ), PL_na ),
		      ItAppLine( table[tab_cnt].ithandle ),
		      table[tab_cnt].leng,
		      char );
	   };
	   tab_cnt++;
	   break;
	 default:
	   /* ignore import parameters */
	   break;
       };

    };

    /* tack on a NULL value parameter to each type to signify that there are no more */
    parameter[exp_cnt].name = NULL;
    parameter[exp_cnt].nlen = 0;
    parameter[exp_cnt].leng = 0;
    parameter[exp_cnt].addr = NULL;
    parameter[exp_cnt].type = 0;

    table[tab_cnt].name = NULL;
    table[tab_cnt].ithandle = NULL;
    table[tab_cnt].nlen = 0;
    table[tab_cnt].leng = 0;
    table[tab_cnt].type = 0;
    /* fprintf(stderr, "sending\n"); */
    rc = RfcSendData( handle, parameter, table );
    /* fprintf(stderr, "after send\n"); */

    return rc;
}


SV* call_handler(SV* sv_callback_handler, SV* sv_iface, SV* sv_data)
{

    int result;
    SV* sv_rvalue;
    dSP;

    /* initialising the argument stack */
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);

    /* push the pkt onto the stack */
    XPUSHs( sv_callback_handler );
    XPUSHs( sv_iface );
    XPUSHs( sv_2mortal( sv_data ) );

    /* add on the TID if one exists */
    if (strlen(current_tid) > 0)
       XPUSHs(newSVpvf("%s", current_tid));

    /* stash the stack point */
    PUTBACK;

    /*result = perl_call_sv(sv_callback_handler, G_EVAL | G_SCALAR ); */
    result = perl_call_pv("SAP::Rfc::Handler", G_EVAL | G_SCALAR );

    /* disassemble the results off the argument stack */
    if(SvTRUE(ERRSV))
        fprintf(stderr, "RFC callback - perl call errored: %s", SvPV(ERRSV,PL_na));
    SPAGAIN;

    /* was this handled or passed? */
    /* fprintf(stderr, "results are: %d \n", result); */
    if (result > 0){
      sv_rvalue = newSVsv(POPs);
    } else {
      sv_rvalue = newSViv(0);
    }
    PUTBACK;
    FREETMPS;
    LEAVE;

    return sv_rvalue;

}


static RFC_RC DLL_CALL_BACK_FUNCTION do_docu(  RFC_HANDLE handle )
{
    RFC_PARAMETER parameter[1];
    RFC_TABLE     table[2];
    RFC_RC        rc;
    RFC_CHAR      read_flag = 0;
    AV*           array;
    int           a_index;
    int           mode;
    char *p;
    int i;

    parameter[0].name = NULL;
    parameter[0].nlen = 0;
    parameter[0].leng = 0;
    parameter[0].addr = NULL;
    parameter[0].type = 0;

    table[0].name =  malloc( 5 );
    memset(table[0].name, 0, 5);
    Copy("DOCU", table[0].name, 4, char);
    table[0].nlen = 4;
    table[0].type = RFCTYPE_CHAR;
    table[0].leng = 80;
    table[0].itmode = RFC_ITMODE_BYREFERENCE;

    table[1].name = NULL;
    table[1].ithandle = NULL;
    table[1].nlen = 0;
    table[1].leng = 0;
    table[1].type = 0;

    rc = RfcGetData( handle, parameter, table );
    if( rc != RFC_OK ) return rc;

    parameter[0].name = NULL;
    parameter[0].nlen = 0;
    parameter[0].leng = 0;
    parameter[0].addr = NULL;
    parameter[0].type = 0;

    table[0].name =  malloc( 5 );
    memset(table[0].name, 0, 5);
    Copy("DOCU", table[0].name, 4, char);
    table[0].nlen = 4;
    table[0].type = RFCTYPE_CHAR;
    table[0].leng = 80;
    table[0].itmode = RFC_ITMODE_BYREFERENCE;

    table[1].name = NULL;
    table[1].ithandle = NULL;
    table[1].nlen = 0;
    table[1].leng = 0;
    table[1].type = 0;
    table[0].ithandle = ItCreate( table[0].name, 80, 0 , 0 );

    /* get the documentation out of the array */
    array = (AV*) SvRV( sv_store_docu );
    a_index = av_len( array );
    for (i = 0; i <= a_index; i++) {
       Copy(  SvPV( *av_fetch( array, i, FALSE ), PL_na ),
	      ItAppLine( table[0].ithandle ), table[0].leng, char );
    };

    rc = RfcSendData( handle, parameter, table );

    return rc;
}


/*
 *
 * function module documentation
 *
 */

/*
 * insert newline characters to start a new line
 */
#undef  NL
#define NL "\n"

static char * do_docu_docu( void )
{
   static char docu[] =
 "This is the override function for the standard self         "      NL
 "discovery documentation function.              "                   NL
 ""                                                                  NL
 "IMPORTING"                                                         NL
 "TABLES"                                                            NL
 "  DOCU           C(80)"                                            NL
 "    internal table contains the documentaiton data.          "     NL
   ;

   return docu;
}










MODULE = SAP::Rfc	PACKAGE = SAP::Rfc	

PROTOTYPES: DISABLE


SV *
MyBcdToChar (sv_bcd)
	SV *	sv_bcd

SV *
MyConnect (sv_handle)
	SV *	sv_handle

SV *
MyAllowStartProgram (sv_program_name)
	SV *	sv_program_name

SV *
MyDisconnect (sv_handle)
	SV *	sv_handle

SV *
MyGetTicket (sv_handle)
	SV *	sv_handle

SV *
MyRfcCallReceive (sv_handle, sv_function, iface)
	SV *	sv_handle
	SV *	sv_function
	SV *	iface

SV *
my_accept (sv_conn, sv_docu, sv_ifaces, sv_saprfc)
	SV *	sv_conn
	SV *	sv_docu
	SV *	sv_ifaces
	SV *	sv_saprfc

