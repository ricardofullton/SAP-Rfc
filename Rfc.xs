#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define MAX_PARA 64

#define RFCIMPORT     0
#define RFCEXPORT     1
#define RFCTABLE      2


#define BUF_SIZE 8192


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


/*
 * local prototypes & declarations
 */

static RFC_RC DLL_CALL_BACK_FUNCTION handle_request( RFC_HANDLE handle, SV* sv_iface );
static RFC_RC DLL_CALL_BACK_FUNCTION do_docu( RFC_HANDLE handle );
static SV* call_handler(SV* sv_callback_handler, SV* sv_iface, SV* sv_data);

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
SV*  MyConnect(SV* connectstring){

    RFC_ENV            new_env;
    RFC_HANDLE         handle;
    RFC_ERROR_INFO_EX  error_info;
    /* RFC_ERROR_INFO  error_info; */
    
    new_env.allocate = NULL;
    new_env.errorhandler = rfc_error;
    RfcEnvironment( &new_env );
    
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
	   hv_store(  hash, mytables[tab_cnt].name, mytables[tab_cnt].nlen, newRV_noinc( (SV*) array = newAV() ), 0);
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



SV* my_accept( SV* sv_conn, SV* sv_docu, SV* sv_ifaces )
{
   /* initialized data */
   static RFC_ENV    env;
   RFC_HANDLE handle;
   RFC_RC     rc;
   RFC_FUNCTIONNAME funcname;
   HV* p_hash;
   SV* sv_iface;

   /*
    * install error handler
    */
   env.errorhandler = rfc_error;
   RfcEnvironment( &env );

   /*
    * accept connection
    *
    * (command line argv must be passed to RfcAccept)
    */
   /* fprintf(stderr, "The connection string is: %s\n", SvPV(sv_conn, SvCUR(sv_conn))); */
   handle = RfcAcceptExt( SvPV(sv_conn, SvCUR(sv_conn)) );

   /*
    * static function to install offered function modules - RFC_DOCU
    */
   rc = install_docu(handle);
   if( rc != RFC_OK )
   {
     RfcAbort( handle, "Initialization error" );
     return newSViv(0);
   }

   sv_store_docu = sv_docu;
   p_hash = (HV*)SvRV( sv_ifaces );

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
    * enter main loop
    */
   do
   {
     /*rc = RfcDispatch( handle ); */
     /* fprintf(stderr, "going to wait ...\n"); */

     rc = RfcGetName(handle, funcname);

     /* fprintf(stderr, "the Function Name is: %s\n", funcname); */

     /* check at this point for registered functions */
     if ( ! hv_exists(p_hash, funcname, strlen(funcname)) ){
       RfcRaise( handle, "FUNCTION Does not exist" );
       continue;
     }

     /* pass in the interface to be handled */
     sv_iface = *hv_fetch(p_hash, funcname, strlen(funcname), FALSE);

     handle_request(handle, sv_iface);

     /* fprintf(stderr, "round the loop ...\n"); */

   } while( rc == RFC_OK );

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
          /* fprintf(stderr, "dont want the handler...\n"); */
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
	   hv_store(  hash, table[tab_cnt].name, table[tab_cnt].nlen, newRV_noinc( (SV*) array = newAV() ), 0);
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

    table[0].name = "DOCU";
    table[0].nlen = 4;
    table[0].type = RFCTYPE_CHAR;
    table[0].leng = 80;
    table[0].itmode = RFC_ITMODE_BYREFERENCE;

    table[1].name = NULL;

    rc = RfcGetData( handle, parameter, table );
    if( rc != RFC_OK ) return rc;

    /* get the documentation out of the array */
    array = (AV*) SvRV( sv_store_docu );
    a_index = av_len( array );
    for (i = 0; i <= a_index; i++) {
       p = (char *) ItAppLine( table[0].ithandle );
       sprintf(p, "%s", SvPV( *av_fetch( array, i, FALSE ), PL_na ));
    };
    parameter[0].name = NULL;

    /* fprintf(stderr, "despatch RFC_DOCU\n"); */
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
MyConnect (sv_handle)
	SV *	sv_handle

SV *
MyDisconnect (sv_handle)
	SV *	sv_handle

SV *
MyRfcCallReceive (sv_handle, sv_function, iface)
	SV *	sv_handle
	SV *	sv_function
	SV *	iface

SV *
my_accept (sv_conn, sv_docu, sv_ifaces)
	SV *	sv_conn
	SV *	sv_docu
	SV *	sv_ifaces

