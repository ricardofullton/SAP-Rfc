#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <saprfc.h>
#include <sapitab.h>

#define MAX_PARA 64

#define RFCIMPORT     0
#define RFCEXPORT     1
#define RFCTABLE      2


#define BUF_SIZE 8192


/* standard error call back handler - installed into connnection object */
static void  DLL_CALL_BACK_FUNCTION  rfc_error( char * operation ){

  RFC_ERROR_INFO_EX  error_info;
  
  //fprintf( stderr, "RFC Call/Exception: %s\n", operation );
  //RfcLastErrorEx(&error_info);
  //fprintf( stderr, "\nGroup       Error group %d", error_info.group );
  //fprintf( stderr, "\nKey         %s", error_info.key );
  //fprintf( stderr, "\nMessage     %s\n", error_info.message );
  //exit(0);
  RfcLastErrorEx(&error_info);
  croak( "RFC Call/Exception: %s \tError group: %d \tKey: %s \tMessage: %s",
      operation,
      error_info.group, 
      error_info.key,
      error_info.message );

}


/* build a connection to an SAP system */
SV*  MyConnect(SV* connectstring){

    RFC_ENV            new_env;
    RFC_HANDLE         handle;
    RFC_ERROR_INFO_EX  error_info;
    
    new_env.allocate = NULL;
    new_env.errorhandler = rfc_error;
    RfcEnvironment( &new_env );
    
    //fprintf(stderr, "CONNECT: %s\n", connectstring);
    handle = RfcOpenEx(SvPV(connectstring, SvCUR(connectstring)),
		       &error_info);

    if (handle == RFC_HANDLE_NULL){
	RfcLastErrorEx(&error_info);
	//fprintf(stderr, "GROUP \t %d \t KEY \t %s \t MESSAGE \t %s \0",
        //         error_info.group, error_info.key, error_info.message );
	//exit(0);
        croak( "RFC Call/Exception: Connection Failed \tError group: %d \tKey: %s \tMessage: %s",
            error_info.group, 
            error_info.key,
            error_info.message );
    };
 
    return newSViv( ( int ) handle );
    
}



/* Disconnect from an SAP system */
SV*  MyDisconnect(SV* sv_handle){

    RFC_HANDLE         handle = SvIV( sv_handle );
    
    RfcClose( handle ); 
    return newSViv(1);

}


/* copy the value of a parameter to a new pointer variable to be passed back onto the 
   parameter pointer argument */
static void * MyValue( SV* type, SV* value, SV* length, int copy ){

    char * ptr;
    int i_value;
    double d_value;

    int len = SvIV( length );
    
    ptr = malloc( len + 1 );
    if ( ptr == NULL )
	return 0;
    memset(ptr, 0, len + 1);
    switch ( SvIV( type ) ){
//      case RFCTYPE_INT:
//      case RFCTYPE_FLOAT:
      default:
/*  All the other SAP internal data types
        case RFCTYPE_CHAR:
        case RFCTYPE_BYTE:
        case RFCTYPE_NUM:
        case RFCTYPE_BCD:
        case RFCTYPE_DATE:
        case RFCTYPE_TIME: */
        if ( copy == TRUE ){
          Copy(SvPV( value, len ), ptr, len, char);
	};
        break;
    };
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
	   myimports[imp_cnt].name = malloc( strlen( SvPV(h_key, PL_na)) + 1 );
	   if ( myimports[imp_cnt].name == NULL )
	       return 0;
	   memset(myimports[imp_cnt].name, 0, strlen( SvPV(h_key, PL_na)) + 1);
	   Copy( SvPV(h_key, PL_na), myimports[imp_cnt].name, strlen( SvPV(h_key, PL_na)), char);
	   myimports[imp_cnt].nlen = strlen( SvPV(h_key, PL_na));
	   myimports[imp_cnt].addr = MyValue(  *hv_fetch(p_hash, (char *) "INTYPE", 6, FALSE),
					       *hv_fetch(p_hash, (char *) "VALUE", 5, FALSE),
					       *hv_fetch(p_hash, (char *) "LEN", 3, FALSE), FALSE );
	   myimports[imp_cnt].leng = SvIV( *hv_fetch( p_hash, (char *) "LEN", 3, FALSE ) );
	   myimports[imp_cnt].type = SvIV( *hv_fetch( p_hash, (char *) "INTYPE", 6, FALSE ) );
	   //fprintf(stderr, "import: %s value: %s \n", myimports[imp_cnt].name, myimports[imp_cnt].addr);
	   ++imp_cnt;
	   break;

	   case RFCEXPORT:
	     /* build an export parameter and pass the value onto the structure */
	   myexports[exp_cnt].name = malloc( strlen( SvPV(h_key, PL_na)) + 1 );
	   if ( myexports[exp_cnt].name == NULL )
	       return 0;
	   memset(myexports[exp_cnt].name, 0, strlen( SvPV(h_key, PL_na)) + 1);
	   Copy( SvPV(h_key, PL_na), myexports[exp_cnt].name, strlen( SvPV(h_key, PL_na)), char);
	   myexports[exp_cnt].nlen = strlen( SvPV(h_key, PL_na));
	   myexports[exp_cnt].addr = MyValue(  *hv_fetch(p_hash, (char *) "INTYPE", 6, FALSE),
					       *hv_fetch(p_hash, (char *) "VALUE", 5, FALSE),
					       *hv_fetch(p_hash, (char *) "LEN", 3, FALSE), TRUE );
	   myexports[exp_cnt].leng = SvIV( *hv_fetch( p_hash, (char *) "LEN", 3, FALSE ) );
	   myexports[exp_cnt].type = SvIV( *hv_fetch( p_hash, (char *) "INTYPE", 6, FALSE ) );
	   //fprintf(stderr, "export: %s value: %s \n", myexports[exp_cnt].name, myexports[exp_cnt].addr);
	   ++exp_cnt;

	   break;

	   case RFCTABLE:
	     /* construct a table parameter and copy the table rows on to the table handle */
	   mytables[tab_cnt].name = malloc( strlen( SvPV(h_key, PL_na)) + 1 );
	   if ( mytables[tab_cnt].name == NULL )
	       return 0;
	   memset(mytables[tab_cnt].name, 0, strlen( SvPV(h_key, PL_na)) + 1);
	   Copy( SvPV(h_key, PL_na), mytables[tab_cnt].name, strlen( SvPV(h_key, PL_na)), char);
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
//	 case RFCTYPE_INT:
//	 case RFCTYPE_FLOAT:
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
	   hv_store(  hash, mytables[tab_cnt].name, mytables[tab_cnt].nlen, newRV_noinc( (SV*) array = newAV() ), 0);
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

