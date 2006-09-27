/*
 *     Copyright (c) 2002 - 2006 Piers Harding.
 *         All rights reserved.
 *
 *         */

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

#ifdef SAPwithUNICODE

#ifdef __cplusplus
extern "C" {
#endif
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include <iconv.h>
#ifdef __cplusplus
}
#endif

static int raise_error = 1;

typedef struct my_iconv_t_struct {
    iconv_t iconv_handle;
    int is_target_utf8;
} *my_iconv_t;

//my_iconv_t global_utf8_to_utf16;
//my_iconv_t global_utf16_to_utf8;

static RFC_UNICODE_TYPE_ELEMENT fieldsOfRFCSI[] =
{
				{ cU("RFCPROTO"),         RFCTYPE_CHAR,  0,     3,    0,   6,    0,   12,   0 },
				{ cU("RFCCHARTYP"),       RFCTYPE_CHAR,  0,     4,    3,   8,    6,   16,  12 },
				{ cU("RFCINTTYP"),        RFCTYPE_CHAR,  0,     3,    7,   6,   14,   12,  28 },
				{ cU("RFCFLOTYP"),        RFCTYPE_CHAR,  0,     3,   10,   6,   20,   12,  40 },
				{ cU("RFCDEST"),          RFCTYPE_CHAR,  0,    32,   13,  64,   26,  128,  52 },
				{ cU("RFCHOST"),          RFCTYPE_CHAR,  0,     8,   45,  16,   90,   32, 180 },
				{ cU("RFCSYSID"),         RFCTYPE_CHAR,  0,     8,   53,  16,  106,   32, 212 },
				{ cU("RFCDATABS"),        RFCTYPE_CHAR,  0,     8,   61,  16,  122,   32, 244 },
				{ cU("RFCDBHOST"),        RFCTYPE_CHAR,  0,    32,   69,  64,  138,  128, 276 },
				{ cU("RFCDBSYS"),         RFCTYPE_CHAR,  0,    10,  101,  20,  202,   40, 404 },
				{ cU("RFCSAPRL"),         RFCTYPE_CHAR,  0,     4,  111,   8,  222,   16, 444 },
				{ cU("RFCMACH"),          RFCTYPE_CHAR,  0,     5,  115,  10,  230,   20, 460 },
				{ cU("RFCOPSYS"),         RFCTYPE_CHAR,  0,    10,  120,  20,  240,   40, 480 },
				{ cU("RFCTZONE"),         RFCTYPE_CHAR,  0,     6,  130,  12,  260,   24, 520 },
				{ cU("RFCDAYST"),         RFCTYPE_CHAR,  0,     1,  136,   2,  272,    4, 544 },
				{ cU("RFCIPADDR"),        RFCTYPE_CHAR,  0,    15,  137,  30,  274,   60, 548 },
				{ cU("RFCKERNRL"),        RFCTYPE_CHAR,  0,     4,  152,   8,  304,   16, 608 },
				{ cU("RFCHOST2"),         RFCTYPE_CHAR,  0,    32,  156,  64,  312,  128, 624 },
				{ cU("RFCSI_RESV"),       RFCTYPE_CHAR,  0,    12,  188,  24,  376,   48, 752 },
};

/*
static RFC_UNICODE_TYPE_ELEMENT fieldsOfRFC_FUNINT[] =
{
				{ "PARAMCLASS",      RFCTYPE_CHAR, 0,    1,    0,   2,    0,    4,    0 },
				{ "PARAMETER",       RFCTYPE_CHAR, 0,   30,    1,  60,    2,  120,    4 },
				{ "TABNAME",         RFCTYPE_CHAR, 0,   30,   31,  60,   62,  120,  124 },
				{ "FIELDNAME",       RFCTYPE_CHAR, 0,   30,   61,  60,  122,  120,  244 },
				{ "EXID",            RFCTYPE_CHAR, 0,    1,   91,   2,  182,    4,  364 },
				{ "POSITION",        RFCTYPE_INT,  0,    4,   92,   4,  184,    4,  368 },
				{ "OFFSET",          RFCTYPE_INT,  0,    4,   96,   4,  188,    4,  372 },
				{ "INTLENGTH",       RFCTYPE_INT,  0,    4,  100,   4,  192,    4,  376 },
				{ "DECIMALS",        RFCTYPE_INT,  0,    4,  104,   4,  196,    4,  380 },
				{ "DEFAULT",         RFCTYPE_CHAR, 0,   21,  108,  42,  200,   84,  384 },
				{ "PARAMTEXT",       RFCTYPE_CHAR, 0,   79,  129, 158,  242,  316,  468 },
				{ "OPTIONAL",        RFCTYPE_CHAR, 0,    1,  208,   2,  400,    4,  784 },
};
*/

typedef struct {
		  SAP_CHAR Paramclass[2];
		  SAP_CHAR Parameter[60];
		  SAP_CHAR Tabname[60];
		  SAP_CHAR Fieldname[60];
		  SAP_CHAR Exid[2];
		  RFC_INT  Position;
		  RFC_INT  Offset;
		  RFC_INT  Intlength;
		  RFC_INT  Decimals;
		  SAP_CHAR Default[42];
		  SAP_CHAR Paramtext[158];
		  SAP_CHAR Optional[2];
} RFC_FUNINT;

#else
static RFC_TYPE_ELEMENT2 fieldsOfRFC_FLDS[] =
{
				{ "TABNAME",         RFCTYPE_CHAR,    30,   0,   0 },
				{ "FIELDNAME",       RFCTYPE_CHAR,    30,   0,  30 },
				{ "POSITION",        RFCTYPE_INT,      4,   0,  60 },
				{ "OFFSET",          RFCTYPE_INT,      4,   0,  64 },
				{ "INTLENGTH",       RFCTYPE_INT,      4,   0,  68 },
				{ "DECIMALS",        RFCTYPE_INT,      4,   0,  72 },
				{ "EXID",            RFCTYPE_CHAR,     1,   0,  76 },
};
RFC_TYPEHANDLE      handleOfRFC_FLDS;

typedef struct {
		  SAP_CHAR Tabname[30];
		  SAP_CHAR Fieldname[30];
		  RFC_INT  Position;
		  RFC_INT  Offset;
		  RFC_INT  Intlength;
		  RFC_INT  Decimals;
		  SAP_CHAR Exid[1]; } RFCFLDS;

static RFC_TYPE_ELEMENT2 fieldsOfRFCSI[] =
{
				{ "RFCPROTO",         RFCTYPE_CHAR,     3,   0,   0 },
				{ "RFCCHARTYP",       RFCTYPE_CHAR,     4,   0,   3 },
				{ "RFCINTTYP",        RFCTYPE_CHAR,     3,   0,   7 },
				{ "RFCFLOTYP",        RFCTYPE_CHAR,     3,   0,  10 },
				{ "RFCDEST",          RFCTYPE_CHAR,    32,   0,  13 },
				{ "RFCHOST",          RFCTYPE_CHAR,     8,   0,  45 },
				{ "RFCSYSID",         RFCTYPE_CHAR,     8,   0,  53 },
				{ "RFCDATABS",        RFCTYPE_CHAR,     8,   0,  61 },
				{ "RFCDBHOST",        RFCTYPE_CHAR,    32,   0,  69 },
				{ "RFCDBSYS",         RFCTYPE_CHAR,    10,   0, 101 },
				{ "RFCSAPRL",         RFCTYPE_CHAR,     4,   0, 111 },
				{ "RFCMACH",          RFCTYPE_CHAR,     5,   0, 115 },
				{ "RFCOPSYS",         RFCTYPE_CHAR,    10,   0, 120 },
				{ "RFCTZONE",         RFCTYPE_CHAR,     6,   0, 130 },
				{ "RFCDAYST",         RFCTYPE_CHAR,     1,   0, 136 },
				{ "RFCIPADDR",        RFCTYPE_CHAR,    15,   0, 137 },
				{ "RFCKERNRL",        RFCTYPE_CHAR,     4,   0, 152 },
				{ "RFCHOST2",         RFCTYPE_CHAR,    32,   0, 156 },
				{ "RFCSI_RESV",       RFCTYPE_CHAR,    12,   0, 188 },
};

/*
static RFC_TYPE_ELEMENT2 fieldsOfRFC_FUNINT[] =
{
				{ "PARAMCLASS",      RFCTYPE_CHAR,     1,   0,   0 },
				{ "PARAMETER",       RFCTYPE_CHAR,    30,   0,   1 },
				{ "TABNAME",         RFCTYPE_CHAR,    30,   0,  31 },
				{ "FIELDNAME",       RFCTYPE_CHAR,    30,   0,  61 },
				{ "EXID",            RFCTYPE_CHAR,     1,   0,  91 },
				{ "POSITION",        RFCTYPE_INT,      4,   0,  92 },
				{ "OFFSET",          RFCTYPE_INT,      4,   0,  96 },
				{ "INTLENGTH",       RFCTYPE_INT,      4,   0, 100 },
				{ "DECIMALS",        RFCTYPE_INT,      4,   0, 104 },
				{ "DEFAULT",         RFCTYPE_CHAR,    21,   0, 108 },
				{ "PARAMTEXT",       RFCTYPE_CHAR,    79,   0, 129 },
				{ "OPTIONAL",        RFCTYPE_CHAR,     1,   0, 208 },
};
*/

typedef struct {
		  SAP_CHAR Paramclass[1];
		  SAP_CHAR Parameter[30];
		  SAP_CHAR Tabname[30];
		  SAP_CHAR Fieldname[30];
		  SAP_CHAR Exid[1];
		  RFC_INT  Position;
		  RFC_INT  Offset;
		  RFC_INT  Intlength;
		  RFC_INT  Decimals;
		  SAP_CHAR Default[21];
		  SAP_CHAR Paramtext[79];
		  SAP_CHAR Optional[1];
} RFC_FUNINT;
#endif

RFC_TYPEHANDLE      handleOfRFCSI;
//RFC_TYPEHANDLE      handleOfRFC_FUNINT;

#define ENTRIES( tab ) ( sizeofR(tab)/sizeofR((tab)[0]) )


/* name of installed function for global callback in tRFC */
#ifdef SAPwithUNICODE
SAP_UC * name_user_global_server = cU("%%USER_GLOBAL_SERVER");
#else
char name_user_global_server[31] = "%%USER_GLOBAL_SERVER";
#endif

/* global hash of interfaces */
SV* global_sv_ifaces;
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
static SAP_UC *user_global_server_docu(void);
static RFC_RC install_docu    ( RFC_HANDLE handle );
static SAP_UC * do_docu_docu( void );

/* store a reference to the documentation array ref */
SV* sv_store_docu;

// fake up a definition of bool if it doesnt exist
#ifndef bool
//typedef unsigned char    bool;
typedef SAP_RAW    bool;
#endif

// create my true and false
#ifndef false
typedef enum { false, true } mybool;
#endif

bool global_init = false;


/* create a parameter space and zero it */
static void * make_space( SV* length ){

    char * ptr;
    int len = SvIV( length );
	  //fprintf(stderr, "make_space...\n");
    
    ptr = malloc( len + 1 );
    //ptr = (char *) New(0, ptr, len+1, char); /* Perl malloc */
    if ( ptr == NULL )
	    return 0;
    memset(ptr, 0, len + 1);
    //memset(ptr, 20, len + 1);
    //*(ptr+(len)) = '\0';
    return ptr;
}


#ifdef SAPwithUNICODE
/* create a parameter space and zero it */
static void * make_space2( int length ){

    char * ptr;
	  //fprintf(stderr, "make_space2...\n");
    
    ptr = malloc( length + 1 );
    //ptr = (char *) New(0, ptr, length+1, char); /* Perl malloc */
    if ( ptr == NULL )
	    return 0;
    memset(ptr, 0, length + 1);
    //memset(ptr, 20, length + 1);
    //*(ptr+(length)) = '\0';
    return ptr;
}
#endif


/* copy the value of a parameter to a new pointer variable to be passed back onto the 
   parameter pointer argument */
static void * make_copy( SV* value, SV* length ){

    char * ptr;
    int len;
		
		len = SvIV( length );
	  //fprintf(stderr, "make_copy ...\n");
    
    ptr = malloc( len + 1 );
    //ptr = (char *) New(0, ptr, len+1, char); /* Perl malloc */
    if ( ptr == NULL )
	    return 0;
    memset(ptr, 0, len + 1);
    //memset(ptr, 20, len + 1);
    //*(ptr+(len)) = '\0';
    //Copy(SvPV( value, len ), ptr, len, char);
		memcpy((char *)ptr, SvPV(value, len), len);
    return ptr;
}


/* copy the value of a parameter to a new pointer variable to be passed back onto the 
   parameter pointer argument without the length supplied */
static void * make_strdup( SV* value ){

    char * ptr;
	  //fprintf(stderr, "make_strdup...\n");
    //int len = strlen(SvPV(value, PL_na));
    int len;
		
		len = SvCUR(value);
    
    ptr = malloc( len + 1 );
    //ptr = (char *) New(0, ptr, len+1, char); /* Perl malloc */
    if ( ptr == NULL )
	    return 0;
    memset(ptr, 0, len + 1);
    //memset(ptr, 20, len + 1);
    //*(ptr+(len)) = '\0';
    //Copy(SvPV( value, len ), ptr, len, char);
		memcpy((char *)ptr, SvPV(value, len), len);
    return ptr;
}

#ifdef SAPwithUNICODE

my_iconv_t  alloc_iconv( char * fromcode, char * tocode ) {
	 my_iconv_t myiconvt;

	 //fprintf(stderr, "alloc_iconv...\n");
   //New(0, myiconvt, 1, struct my_iconv_t_struct);
   myiconvt = malloc(sizeof(struct my_iconv_t_struct));
	 memset(myiconvt, 0,sizeof(struct my_iconv_t_struct)); 

   if((myiconvt->iconv_handle = iconv_open(tocode, fromcode)) == (iconv_t)-1)
   {
      switch(errno)
      {
	 case ENOMEM:
	    croak("Insufficient memory to initialize conversion: %s -> %s",
                  fromcode, tocode);
	 case EINVAL:
	    croak("Unsupported conversion: %s -> %s", fromcode, tocode);
	 default:
	    croak("Couldn't initialize conversion: %s -> %s", fromcode, tocode);
      }
   }
   myiconvt->is_target_utf8 =  (!strcmp(tocode,"UTF-8") || !strcmp(tocode,"utf-8"));

	 return myiconvt;
}

void dealloc_iconv(my_iconv_t myiconvt) {
    
	 //fprintf(stderr, "dealloc_iconv...\n");
		iconv_close(myiconvt->iconv_handle);
		free(myiconvt);
}


char *u_doconv8to16str(iconv_t iconv_handle, SV *string, int is_target_utf8, int *final, bool pad)
{
   char    *ibuf;         /* char* to the content of SV *string */
   char    *obuf;         /* temporary output buffer */
   size_t  inbytesleft;   /* no. of bytes left to convert; initially
			     this is the length of the input string,
			     and 0 when the conversion has finished */
   size_t  outbytesleft;  /* no. of bytes in the output buffer */
   size_t  l_obuf;        /* length of the output buffer */
   char *icursor;         /* current position in the input buffer */
   /* The Single UNIX Specification (version 1 and version 2), as well
      as the HP-UX documentation from which the XPG iconv specs are
      derived, are unclear about the type of the second argument to
      iconv() (here called icursor): The manpages say const char **,
      while the header files say char **. */
   char    *ocursor;      /* current position in the output buffer */
   size_t  ret;           /* iconv() return value */
	 char * res;
	 int fsize;
	 int orig;

	 //fprintf(stderr, "u_doconv8to16str...\n");
	 //fprintf(stderr, "converting: %s#%d\n", SvPV(string, SvCUR(string)), SvCUR(string));

   /* Get length of input string. That's why we take an SV* instead of
      a char*: This way we can convert UCS-2 strings because we know
      their length. */

   inbytesleft = SvCUR(string);
	 orig = inbytesleft;
   //ibuf        = SvPV(string, inbytesleft);
   ibuf   = make_strdup(string);

   /* Calculate approximate amount of memory needed for the temporary
      output buffer and reserve the memory. The idea is to choose it
      large enough from the beginning to reduce the number of copy
      operations when converting from a single byte to a multibyte
      encoding. */

	 //fprintf(stderr, "MB_LENMAX: %d\n", MB_LEN_MAX);
	 //fprintf(stderr, "inbytesleft: %d\n", inbytesleft);
	 /*
   if(inbytesleft <= MB_LEN_MAX)
   {
      outbytesleft = MB_LEN_MAX + 1;
   }
   else
   {
	 */
      outbytesleft = 2 * inbytesleft;
   //}
   outbytesleft += MB_LEN_MAX;

	 /* give a crude mechanism of 10% extra + 10 */
	 //fprintf(stderr, "outbytes calculated(1): %d\n", outbytesleft);
	 //outbytesleft += (outbytesleft * 0.1);
	 //outbytesleft += 10;

	 //fprintf(stderr, "outbytes calculated: %d\n", outbytesleft);

   l_obuf = outbytesleft;
   //obuf   = (char *) New(0, obuf, outbytesleft, char); /* Perl malloc */
   obuf   = malloc(outbytesleft);
   memset(obuf, 0, outbytesleft);

   /**************************************************************************/

   icursor = ibuf;
   ocursor = obuf;

   /**************************************************************************/

   while(inbytesleft != 0)
   {
      ret = iconv(iconv_handle, (const char**)&icursor, &inbytesleft, &ocursor, &outbytesleft);

      if(ret == (size_t) -1)
      {
	 switch(errno)
	 {
	    case EILSEQ:
	       /* Stop conversion if input character encountered which
		  does not belong to the input char set */
	       if (raise_error)
		  croak("Character not from source char set: %s",
			strerror(errno));
	       free(obuf);
	       return(NULL);
	    case EINVAL:
	       /* Stop conversion if we encounter an incomplete
                  character or shift sequence */
	       if (raise_error)
		  croak("Incomplete character or shift sequence: %s",
			strerror(errno));
	       free(obuf);
	       return(NULL);
	    case E2BIG:
	       /* If the output buffer is not large enough, copy the
                  converted bytes to the return string, reset the
                  output buffer and continue */
				 //fprintf(stderr, "Not enough OBUF - short circuiting\n");
				 inbytesleft = 0;
	       //sv_catpvn(perl_str, obuf, l_obuf - outbytesleft);
	       //fprintf(stderr, "NOW outbytes: %d l_obuf: %d\n", outbytesleft, l_obuf);
	       fprintf(stderr, "copying part length: %d\n", (int) (l_obuf - outbytesleft));
	       ocursor = obuf;
	       outbytesleft = l_obuf;
		     croak("run out of output space for receiving characters: %s",
			      strerror(errno));
				 exit(-1);
	       break;
	    default:
	       if (raise_error)
		  croak("iconv error: %s", strerror(errno));
	       free(obuf);
	       return(NULL);
	 }
      }
   }

   /* Copy the converted bytes to the return string, and free the
      output buffer */

   //fprintf(stderr, "copying final length: %d\n", l_obuf - outbytesleft);
   //sv_catpvn(perl_str, obuf, l_obuf - outbytesleft);
   //perl_str =  newSVpvn(obuf, l_obuf - outbytesleft);
   free(ibuf); /* Perl malloc */

//#ifdef SvUTF8_on
//   if (is_target_utf8) {
//      SvUTF8_on(perl_str);
//   } else {
//      SvUTF8_off(perl_str);
//   }
//#endif

	 //fprintfU(stderr, cU("Finished: %s#%d\n"), SvPV(perl_str, SvCUR(perl_str)), SvCUR(perl_str));
	 //fprintfU(stderr, cU("Obuf is: %s#\n"), obuf);
	 if (!pad){
	   fsize = l_obuf - outbytesleft;
	   res = malloc(fsize+2);
	   memset(res, 0, fsize+2);
	   memcpy((char *)res, obuf, fsize);
           //fprintf(stderr, "NO PADDING!!!\n"); 
	 } else {
	   fsize = orig*2;
	   res = malloc(fsize+2);
	   //memset(res, 0, fsize+1);
	   memsetU((SAP_UC *)res, cU(' '), orig);
	   *(res+fsize) = '\0';
	   *(res+(fsize+1)) = '\0';
	   memcpy((char *)res, obuf, l_obuf - outbytesleft);
           //fprintf(stderr, "PAD THIS ONE!!! %d/%d \n", orig*2, l_obuf - outbytesleft); 
           //if ((l_obuf - outbytesleft) > (orig*2)){
           //  fprintf(stderr, "really bad problem!!!\n");
           //}
	 }
         *final = fsize;
	 free(obuf);
	 icursor = NULL;
	 ibuf    = NULL;
	 obuf    = NULL;
	 ocursor = NULL;

	 //fprintfU(stderr, cU("Finished: %s#%d pad: %d\n"), res, strlenU(res), (int) pad);
   return res;
}


SV *u_doconv16to8str(iconv_t iconv_handle, char *string, int ilen, int is_target_utf8)
{
   char    *ibuf;         /* char* to the content of SV *string */
   char    *obuf;         /* temporary output buffer */
   size_t  inbytesleft;   /* no. of bytes left to convert; initially
			     this is the length of the input string,
			     and 0 when the conversion has finished */
   size_t  outbytesleft;  /* no. of bytes in the output buffer */
   size_t  l_obuf;        /* length of the output buffer */
   char *icursor;         /* current position in the input buffer */
   /* The Single UNIX Specification (version 1 and version 2), as well
      as the HP-UX documentation from which the XPG iconv specs are
      derived, are unclear about the type of the second argument to
      iconv() (here called icursor): The manpages say const char **,
      while the header files say char **. */
   char    *ocursor;      /* current position in the output buffer */
   size_t  ret;           /* iconv() return value */
   SV      *perl_str;     /* Perl return string */

	 //fprintf(stderr, "u_doconv16to8...\n");
   perl_str = newSVpv("", 0);
	 //fprintfU(stderr, cU("converting: %s#%d\n"), string, ilen);

   /* Get length of input string. That's why we take an SV* instead of
      a char*: This way we can convert UCS-2 strings because we know
      their length. */

   inbytesleft = ilen;
   //ibuf        = SvPV(string, inbytesleft);
   ibuf   = string;

   /* Calculate approximate amount of memory needed for the temporary
      output buffer and reserve the memory. The idea is to choose it
      large enough from the beginning to reduce the number of copy
      operations when converting from a single byte to a multibyte
      encoding. */

	 //fprintf(stderr, "MB_LENMAX: %d\n", MB_LEN_MAX);
	 //fprintf(stderr, "inbytesleft: %d\n", inbytesleft);
	 /*
   if(inbytesleft <= MB_LEN_MAX)
   {
      outbytesleft = MB_LEN_MAX + 1;
   }
   else
   {
	 */
      //outbytesleft = 2 * inbytesleft;
      outbytesleft = inbytesleft;
   //}
   outbytesleft += MB_LEN_MAX;

	 /* give a crude mechanism of 10% extra + 10 */
	 //fprintf(stderr, "outbytes calculated(1): %d\n", outbytesleft);
	 //outbytesleft += (outbytesleft * 0.1);
	 //outbytesleft += 10;

	 //fprintf(stderr, "outbytes calculated: %d\n", outbytesleft);

   l_obuf = outbytesleft;
   //obuf   = (char *) New(0, obuf, outbytesleft, char); /* Perl malloc */
   obuf   = malloc(outbytesleft);
	 memset(obuf, 0, outbytesleft);

   /**************************************************************************/

   icursor = ibuf;
   ocursor = obuf;

   /**************************************************************************/

   while(inbytesleft != 0)
   {
      ret = iconv(iconv_handle, (const char**)&icursor, &inbytesleft, &ocursor, &outbytesleft);

      if(ret == (size_t) -1)
      {
	 switch(errno)
	 {
	    case EILSEQ:
	       /* Stop conversion if input character encountered which
		  does not belong to the input char set */
	       if (raise_error)
		  croak("Character not from source char set: %s",
			strerror(errno));
	       free(obuf);
	       return(&PL_sv_undef);
	    case EINVAL:
	       /* Stop conversion if we encounter an incomplete
                  character or shift sequence */
	       if (raise_error)
		  croak("Incomplete character or shift sequence: %s",
			strerror(errno));
	       free(obuf);
	       return(&PL_sv_undef);
	    case E2BIG:
	       /* If the output buffer is not large enough, copy the
                  converted bytes to the return string, reset the
                  output buffer and continue */
				 //fprintf(stderr, "Not enough OBUF - short circuiting\n");
				 inbytesleft = 0;
	       sv_catpvn(perl_str, obuf, l_obuf - outbytesleft);
	       //fprintf(stderr, "NOW outbytes: %d l_obuf: %d\n", outbytesleft, l_obuf);
	       //fprintf(stderr, "copying part length: %d\n", l_obuf - outbytesleft);
	       ocursor = obuf;
	       outbytesleft = l_obuf;
		     //croak("run out of output space for receiving characters: %s",
			   //   strerror(errno));
	       //return(&PL_sv_undef);
	       break;
	    default:
	       if (raise_error)
		  croak("iconv error: %s", strerror(errno));
	       free(obuf);
	       return(&PL_sv_undef);
	 }
      }
   }

   /* Copy the converted bytes to the return string, and free the
      output buffer */

	 //fprintf(stderr, "copying final length: %d\n", l_obuf - outbytesleft);
   sv_catpvn(perl_str, obuf, l_obuf - outbytesleft);
   //perl_str =  newSVpvn(obuf, l_obuf - outbytesleft);
   free(obuf); /* Perl malloc */

//#ifdef SvUTF8_on
//   if (is_target_utf8) {
//      SvUTF8_on(perl_str);
//   } else {
/* switched off UTF-8 Flag XXX */
	 SvUTF8_off(perl_str);
//   }
//#endif

	 icursor = NULL;
	 ibuf    = NULL;
	 ocursor = NULL;
	 //fprintf(stderr, "Finished: %s#%d\n", SvPV(perl_str, SvCUR(perl_str)), SvCUR(perl_str));
   return perl_str;
}


char * u8to16( SV* string) {
	char * str;
        int final;
	  //fprintf(stderr, "u8to16...\n");
  my_iconv_t myiconvt = alloc_iconv("UTF-8", "UTF-16LE");
  str = u_doconv8to16str(myiconvt->iconv_handle, string, myiconvt->is_target_utf8, &final, false);
	dealloc_iconv(myiconvt);
	return str;
}


char * u8to16l( SV* string, int *final) {
	char * str;
	  //fprintf(stderr, "u8to16...\n");
  my_iconv_t myiconvt = alloc_iconv("UTF-8", "UTF-16LE");
  str = u_doconv8to16str(myiconvt->iconv_handle, string, myiconvt->is_target_utf8, final, true);
	dealloc_iconv(myiconvt);
	return str;
}


char * u8to16p( SV* string) {
	char * str;
  int final;
	  //fprintf(stderr, "u8to16...\n");
  my_iconv_t myiconvt = alloc_iconv("UTF-8", "UTF-16LE");
  str = u_doconv8to16str(myiconvt->iconv_handle, string, myiconvt->is_target_utf8, &final, true);
	dealloc_iconv(myiconvt);
	return str;
}


SV* u16to8(char * string, int ilen) {
	SV* perl_str;
	//fprintf(stderr, "u16to8...\n");
	my_iconv_t myiconvt = alloc_iconv("UTF-16LE", "UTF-8");
  perl_str = u_doconv16to8str(myiconvt->iconv_handle, string, ilen, myiconvt->is_target_utf8);
	dealloc_iconv(myiconvt);
	return perl_str;
}


SV* MyInit(void) {

		int rc;
	  //fprintf(stderr, "Init...\n");
		if (!global_init) {

      rc = RfcInstallUnicodeStructure(cU("RFCSI"),
		                                  fieldsOfRFCSI,
		                                  ENTRIES(fieldsOfRFCSI),
				   													 0, NULL,
                                      &handleOfRFCSI);
/*
			rc = RfcInstallUnicodeStructure(cU("RFC_FUNINT"),
		                                  fieldsOfRFC_FUNINT,
		                                  ENTRIES(fieldsOfRFC_FUNINT),
				   													 0, NULL,
                                      &handleOfRFC_FUNINT);
*/
//      global_utf8_to_utf16 =  alloc_iconv("UTF-8", "UTF-16LE");
//      global_utf16_to_utf8 =  alloc_iconv("UTF-16LE", "UTF-8");
		  global_init = true;
		}
		return newSViv(global_init);
}

#else

SV* MyInit(void) {
		int rc;
	  //fprintf(stderr, "Init...\n");
		if (!global_init) {
		  rc = RfcInstallStructure2("RFC_FLDS",
		                            fieldsOfRFC_FLDS,
		                            ENTRIES(fieldsOfRFC_FLDS),
		                            &handleOfRFC_FLDS );

			rc = RfcInstallStructure2("RFCSI",
		                            fieldsOfRFCSI,
		                            ENTRIES(fieldsOfRFCSI),
		                            &handleOfRFCSI );
/*
			rc = RfcInstallStructure2("RFC_FUNINT",
		                            fieldsOfRFC_FUNINT,
		                            ENTRIES(fieldsOfRFC_FUNINT),
		                            &handleOfRFC_FUNINT );
																*/
		  global_init = true;
		}
		return newSViv(global_init);
}
#endif


/* standard error call back handler - installed into connnection object */
static void  DLL_CALL_BACK_FUNCTION  rfc_error( SAP_UC * operation ){
  RFC_ERROR_INFO_EX  error_info;
  
	  //fprintf(stderr, "rfc_error...\n");
  RfcLastErrorEx(&error_info);
  croak( "RFC Call/Exception: %s \tError group: %d \tKey: %s \tMessage: %s",
      operation,
      error_info.group, 
      error_info.key,
      error_info.message );
}


/* build a connection to an SAP system */
SV*  MyBcdToChar(SV* sv_bcd){
  int   rc,
        bcd_char_len,
        bcd_num_len,
        decimal_no;

  char           bcd_char[33];
  unsigned char  bcd_num[16];

	  //fprintf(stderr, "BcdToChar...\n");
  bcd_char_len = 4;
  bcd_num_len = 3;
  decimal_no = 1;
  memset(bcd_num+0, 0, sizeof(bcd_num));
  memset(bcd_char+0, 0, sizeof(bcd_char));
  //Copy(SvPV( sv_bcd, 2 ), (char *) bcd_num, 2, char);
  memcpy((char *)bcd_num+0, SvPV(sv_bcd, SvCUR(sv_bcd)), 3);

  //rc = RfcConvertBcdToChar((RFC_BCD *) SvPV(sv_bcd, SvCUR(sv_bcd)),
  rc = RfcConvertBcdToChar((RFC_BCD *) bcd_num,
                           bcd_num_len,
                           decimal_no,
                           (RFC_CHAR *) bcd_char,
                           bcd_char_len);
  //memset(bcd_char+0, 0, 32 + 1);
  //fprintf(stderr, "new bcd: %s#\n", bcd_char);
  return newSViv(1);
}


/* build a connection to an SAP system */
SV*  MyIsUnicode( ){
        
	 // fprintf(stderr, "IsUnicode...\n");
#ifdef SAPwithUNICODE
   return newSViv(1);
#else
   return newSViv(0);
#endif
}


/* build a connection to an SAP system */
SV*  MyConnect(SV* connectstring){

    RFC_ENV            new_env;
    RFC_HANDLE         handle;
    RFC_ERROR_INFO_EX  error_info;
#ifdef SAPwithUNICODE
		char *ptr;
		SV* sv_temp;
#endif
    
	  //fprintf(stderr, "Connect...\n");
    new_env.allocate = NULL;
    new_env.errorhandler = rfc_error;
    RfcEnvironment( &new_env );
    
#ifdef SAPwithUNICODE
    ptr = u8to16(connectstring);
    handle = RfcOpenEx((rfc_char_t *)ptr, &error_info);
		free(ptr);
#else
    handle = RfcOpenEx((rfc_char_t *)SvPV(connectstring, SvCUR(connectstring)),
		       &error_info);
#endif

    if (handle == RFC_HANDLE_NULL){
     	RfcLastErrorEx(&error_info);
#ifdef SAPwithUNICODE
			sv_temp = newSVpv("RFC Call/Exception: Connection Failed \tError group: ", 52);
	    sv_catsv(sv_temp, newSVpvf("%d", error_info.group));
	    sv_catpvn(sv_temp, "\tKey: ", 6);
	    sv_catsv(sv_temp, u16to8((char *)error_info.key, strlenU(error_info.key)*2));
	    sv_catpvn(sv_temp, "\tMessage: ", 10);
	    sv_catsv(sv_temp, u16to8((char *)error_info.message, strlenU(error_info.message)*2));
      croak(SvPV(sv_temp, PL_na)); 
#else
      croak( "RFC Call/Exception: Connection Failed \tError group: %d \tKey: %s \tMessage: %s",
            error_info.group, 
            error_info.key,
            error_info.message );
#endif
    };
 
    return newSViv( ( int ) handle );
}


/* Disconnect from an SAP system */
SV*  MyDisconnect(SV* sv_handle){

    RFC_HANDLE         handle = SvIV( sv_handle );
	  //fprintf(stderr, "Disconnect...\n");
    
    RfcClose( handle ); 
    return newSViv(1);
}


SV* MyGetTicket(SV* sv_handle){

		RFC_HANDLE handle;
    RFC_RC rc;
    RFC_ERROR_INFO_EX  error_info;
    char ticket[4096];
    HV* hash = newHV();

	  //fprintf(stderr, "GetTicket...\n");
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

/* RfcAllow */
SV*  MyAllowStartProgram(SV* sv_program_name){
  
   RfcAllowStartProgram( SvPV(sv_program_name, PL_na) );
   return newSViv(1);
}                                                                                                


/* build the RFC call interface, do the RFC call, and then build a complex
  hash structure of the results to pass back into ruby */
SV* MyGetStructure(SV* sv_handle, SV* sv_structure){

#ifdef SAPwithUNICODE
   RFC_RC             rc;
   RFC_HANDLE         handle;
   SAP_UC *           exception;
	 SAP_UC             errstr[2048];
   RFC_ERROR_INFO_EX  error_info;
	 char *							ptr;

   int                irow;
   RFC_U_FIELDS *tFields;
	 unsigned pb1slen, pb2slen, pb4slen;
	 RFCTYPE ptypekind;
	 RFC_STRUCT_TYPE_ID psid;
	 ITAB_H i_tabh;

   AV*                array;
   HV*                hash;


	 //fprintf(stderr, "Get structure...\n");
   handle = SvIV( sv_handle );

   ptr = u8to16(sv_structure);
   rc =  RfcGetStructureInfoAsTable( handle, 
				    (SAP_CHAR *) ptr,
				    &i_tabh,
				    NULL,
						&ptypekind,
						&pb1slen,
						&pb2slen,
						&pb4slen,
						&psid,
				    &exception );
   free(ptr);
	 /* check the return code - if necessary construct an error message */
   if ( rc != RFC_OK ){
       RfcLastErrorEx( &error_info );
     if (( rc == RFC_EXCEPTION ) ||
         ( rc == RFC_SYS_EXCEPTION )) {
	     sprintfU(errstr, cU("EXCEPT\t%s\tGROUP\t%d\tKEY\t%s\tMESSAGE\t%s"), exception, error_info.group, error_info.key, error_info.message );
     } else {
	     sprintfU(errstr, cU("EXCEPT\t%s\tGROUP\t%d\tKEY\t%s\tMESSAGE\t%s"),cU("RfcGetStructureInfoAsTable"), error_info.group, error_info.key, error_info.message);
     };
		 fprintfU(stderr,cU("%s"), errstr);
		 exit(-1);
   };

	 array = newAV();
   for (irow = 1; irow <= ItFill(i_tabh); irow++){
       tFields = ItGetLine(i_tabh, irow);
       hash = newHV();
	     hv_store(hash, "tabname", 7, u16to8((char *)tFields->Tabname, 60), 0);
	     hv_store(hash, "fieldname", 9, u16to8((char *)tFields->Fieldname, 60), 0);
	     hv_store(hash, "exid", 4, u16to8((char *)tFields->Exid, 2), 0);
	     hv_store(hash, "pos", 3, newSViv(tFields->Position), 0);
	     hv_store(hash, "dec", 3, newSViv(tFields->Decimals), 0);
	     hv_store(hash, "off1", 4, newSViv(tFields->Offset_b1), 0);
	     hv_store(hash, "len1", 4, newSViv(tFields->Length_b1), 0);
	     hv_store(hash, "off2", 4, newSViv(tFields->Offset_b2), 0);
	     hv_store(hash, "len2", 4, newSViv(tFields->Length_b2), 0);
	     hv_store(hash, "off4", 4, newSViv(tFields->Offset_b4), 0);
	     hv_store(hash, "len4", 4, newSViv(tFields->Length_b4), 0);
	     av_push(array, newRV_noinc( (SV*) hash));
			 //fprintfU(stderr, cU("row: %s/%s type: %s #\n"), tFields->Tabname, tFields->Fieldname, tFields->Exid);
			 //fprintfU(stderr, cU("pos: %d dec: %d off2: %d len2: %d #\n"), tFields->Position, tFields->Decimals, tFields->Offset_b2, tFields->Length_b2);
   };
   ItFree(i_tabh);
   hash = newHV();
	 hv_store(hash, "type", 4, newSViv(ptypekind), 0);
	 hv_store(hash, "b1len", 5, newSViv(pb1slen), 0);
	 hv_store(hash, "b2len", 5, newSViv(pb2slen), 0);
	 hv_store(hash, "b4len", 5, newSViv(pb4slen), 0);
	 av_push(array, newRV_noinc( (SV*) hash));


	 //fprintf(stderr, "returning from GetStructure...\n");
	 return newRV_noinc((SV*) array);
#else

   RFC_PARAMETER      myexports[MAX_PARA];
   RFC_PARAMETER      myimports[MAX_PARA];
   RFC_TABLE          mytables[MAX_PARA];
   RFC_RC             rc;
   RFC_HANDLE         handle;
   SAP_UC *           exception;
	 SAP_UC             errstr[1024];
   RFC_ERROR_INFO_EX  error_info;

   int                tab_cnt, 
                      imp_cnt,
                      exp_cnt,
                      irow,
											tablength;
   RFCFLDS * tFields;

   AV*                array;
   HV*                hash;

   handle = SvIV( sv_handle );

   tab_cnt = 0;
   exp_cnt = 0;
   imp_cnt = 0;

	 myexports[exp_cnt].name = "TABNAME";
	 myexports[exp_cnt].nlen = strlen(myexports[exp_cnt].name);
	 myexports[exp_cnt].type = RFCTYPE_CHAR;
	 myexports[exp_cnt].addr = make_strdup(sv_structure);
	 myexports[exp_cnt].leng = strlen(myexports[exp_cnt].addr);
   exp_cnt++;
	 myimports[imp_cnt].name = "TABLENGTH";
	 myimports[imp_cnt].nlen = strlen(myimports[imp_cnt].name);
	 myimports[imp_cnt].type = RFCTYPE_INT;
	 myimports[imp_cnt].addr = &tablength;
	 myimports[imp_cnt].leng = 4;
   imp_cnt++;
	 mytables[tab_cnt].name = "FIELDS";
	 mytables[tab_cnt].nlen = strlen(mytables[tab_cnt].name);
   mytables[tab_cnt].ithandle = ItCreate( "FIELDS", 80, 0 , 0 );
	 mytables[tab_cnt].leng = 80; //B1 length
   mytables[tab_cnt].itmode = RFC_ITMODE_BYREFERENCE;
   mytables[tab_cnt].type = handleOfRFC_FLDS; 
	 tab_cnt++;

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

   rc =  RfcCallReceive( handle, "RFC_GET_STRUCTURE_DEFINITION",
				    myexports,
				    myimports,
				    mytables,
				    &exception );


   /* check the return code - if necessary construct an error message */
   if ( rc != RFC_OK ){
       RfcLastErrorEx( &error_info );
     if (( rc == RFC_EXCEPTION ) ||
         ( rc == RFC_SYS_EXCEPTION )) {
	     sprintf(errstr, "EXCEPT\t%s\tGROUP\t%d\tKEY\t%s\tMESSAGE\t%s", exception, error_info.group, error_info.key, error_info.message );
     } else {
	     sprintf(errstr, "EXCEPT\t%s\tGROUP\t%d\tKEY\t%s\tMESSAGE\t%s","RfcCallReceive", error_info.group, error_info.key, error_info.message);
     };
		 fprintf(stderr,"%s", errstr);
		 exit(-1);
   };

   /* free up the used memory for export parameters */
   for (exp_cnt = 0; exp_cnt < MAX_PARA; exp_cnt++){
       if ( myexports[exp_cnt].name == NULL ){
	       break;
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

   
   /* retrieve the values of the table parameters and free up the memory */
   tab_cnt = 0;
	 array = newAV();
   /*  grab each table row and push onto an array */
   for (irow = 1; irow <=  ItFill(mytables[tab_cnt].ithandle); irow++){
       tFields = ItGetLine(mytables[tab_cnt].ithandle, irow);
       hash = newHV();
	     hv_store(hash, "tabname", 7, newSVpv(tFields->Tabname, 30), 0);
	     hv_store(hash, "fieldname", 9, newSVpv(tFields->Fieldname, 30), 0);
	     hv_store(hash, "exid", 4, newSVpv(tFields->Exid, 1), 0);
	     hv_store(hash, "pos", 3, newSViv(tFields->Position), 0);
	     hv_store(hash, "dec", 3, newSViv(tFields->Decimals), 0);
	     hv_store(hash, "off", 3, newSViv(tFields->Offset), 0);
	     hv_store(hash, "len", 3, newSViv(tFields->Intlength), 0);
	     av_push(array, newRV_noinc( (SV*) hash));
   };
	   
   hash = newHV();
	 hv_store(hash, "tablength", 9, newSViv(tablength), 0);
	 av_push(array, newRV_noinc( (SV*) hash));
   mytables[tab_cnt].name = NULL;
   if ( mytables[tab_cnt].ithandle != NULL ){
    ItFree( mytables[tab_cnt].ithandle );
   };
   mytables[tab_cnt].ithandle = NULL;
   mytables[tab_cnt].nlen = 0;
   mytables[tab_cnt].leng = 0;
   mytables[tab_cnt].type = 0;

	 return newRV_noinc((SV*) array);
#endif
}


/* build the RFC call interface, do the RFC call, and then build a complex
  hash structure of the results to pass back into ruby */
SV* MyInstallStructure(SV* sv_handle, SV* sv_structure){

#ifdef SAPwithUNICODE
   RFC_RC             rc;
   RFC_HANDLE         handle;
   SAP_UC *           name;
	 SAP_UC             errstr[2048];
	 char * 						ptr;
   RFC_ERROR_INFO_EX  error_info;
   int                a_index,
                      i;
   AV*                data;
   HV*                h_struct;
   HV*                hash;
   RFC_UNICODE_TYPE_ELEMENT * utype;
	 RFC_TYPEHANDLE type_handle;
	 RFCTYPE rfc_type;

	 //fprintf(stderr, "Install structure...\n");
   handle = SvIV( sv_handle );
   h_struct =  (HV*)SvRV(sv_structure);
	 data = (AV*) SvRV(*hv_fetch(h_struct, (char *) "DATA", 4, FALSE));
	 name = (SAP_UC *) u8to16(*hv_fetch(h_struct, (char *) "NAME", 4, FALSE));

	 /* make sure that there are some fields  */
	 a_index = av_len(data);

	 utype = malloc((a_index+1)*sizeof(RFC_UNICODE_TYPE_ELEMENT));
	 memset(utype, 0,(a_index+1)*sizeof(RFC_UNICODE_TYPE_ELEMENT)); 

	 for (i=0; i <= a_index; i++) {
	   hash = (HV*) SvRV(*av_fetch(data, i, FALSE));
		 utype[i].name = (SAP_UC *) u8to16(*hv_fetch(hash, (char *) "fieldname", 9, FALSE));
		 ptr = u8to16(*hv_fetch(hash, (char *) "exid", 4, FALSE));
		 rc = RfcExidToRfcType(*ptr, &rfc_type);
		 free(ptr);
		 if (rc != RFC_OK) {
			 fprintfU(stderr, cU("RFC Type conversion failed!\n"));
			 exit(-1);
		 }
     utype[i].type = rfc_type;
		 utype[i].decimals = SvIV(*hv_fetch(hash, (char *) "dec", 3, FALSE));
     utype[i].c1_length = SvIV(*hv_fetch(hash, (char *) "len1", 4, FALSE));
     utype[i].c1_offset = SvIV(*hv_fetch(hash, (char *) "off1", 4, FALSE));
     utype[i].c2_length = SvIV(*hv_fetch(hash, (char *) "len2", 4, FALSE));
     utype[i].c2_offset = SvIV(*hv_fetch(hash, (char *) "off2", 4, FALSE));
     utype[i].c4_length = SvIV(*hv_fetch(hash, (char *) "len4", 4, FALSE));
     utype[i].c4_offset = SvIV(*hv_fetch(hash, (char *) "off4", 4, FALSE));
		 //fprintfU(stderr, cU("field: %s type: %d dec: %d len1: %d off1: %d len2: %d off2: %d len4: %d off4: %d \n"),
     //utype[i].name, utype[i].type, utype[i].decimals, utype[i].c1_length, utype[i].c1_offset, utype[i].c2_length, utype[i].c2_offset, utype[i].c4_length, utype[i].c4_offset
		//								 );
   }

	 //fprintf(stderr, "executing InstallUnicodeStructure...\n");
   rc = RfcInstallUnicodeStructure(name,
                                   utype,
                                   a_index + 1,
																	 0, NULL,
                                   &type_handle);
	 //fprintf(stderr, "AFTER executing InstallUnicodeStructure...\n");
	 free(name);
	 //fprintf(stderr, "FREE...\n");
	 for (i=0; i <= a_index; i++) {
     free(utype[i].name);
   }
	 //fprintf(stderr, "FREE...\n");
   free(utype);
	 //fprintf(stderr, "FREE...\n");

   /* check the return code - if necessary construct an error message */
   if ( rc != RFC_OK ){
       RfcLastErrorEx( &error_info );
     if (( rc == RFC_EXCEPTION ) ||
         ( rc == RFC_SYS_EXCEPTION )) {
#ifdef _WIN32
       sprintfU(errstr, cU("KEY\t%s\tMESSAGE\t%s"), error_info.key, error_info.message );
#else
       sprintfU(errstr, cU("GROUP\t%d\tKEY\t%s\tMESSAGE\t%s"), error_info.group, error_info.key, error_info.message );
#endif
     } else {
	     sprintfU(errstr, cU("EXCEPT\t%s\tGROUP\t%d\tKEY\t%s\tMESSAGE\t%s"), cU("RfcCallReceive"), error_info.group, error_info.key, error_info.message);
     };
		 fprintfU(stderr,cU("%s"), errstr);
		 exit(-1);
   };

	 //fprintf(stderr, "RETURN %d  ...\n", type_handle);
   return newSViv(type_handle);

#else

   RFC_RC             rc;
   RFC_HANDLE         handle;
	 SAP_UC             errstr[1024];
   SAP_UC *           name;
   RFC_ERROR_INFO_EX  error_info;
	 char rfc_type_c;

   int                a_index,
                      i;
   AV*                data;
   HV*                h_struct;
   HV*                hash;
   RFC_TYPE_ELEMENT2 * type2;
	 RFC_TYPEHANDLE type_handle;
	 RFCTYPE rfc_type;
	 //fprintf(stderr, "InstallStructure ...\n");

   handle = SvIV( sv_handle );
   h_struct =  (HV*)SvRV(sv_structure);
	 data = (AV*) SvRV(*hv_fetch(h_struct, (char *) "DATA", 4, FALSE));
	 a_index = av_len(data);
	 name = (SAP_UC *) make_strdup(*hv_fetch(h_struct, (char *) "NAME", 4, FALSE));
	 //fprintf(stderr, "structure: %s\n", name);

	 type2 = malloc((a_index+1)*sizeof(RFC_TYPE_ELEMENT2));
	 memset(type2, 0,(a_index+1)*sizeof(RFC_TYPE_ELEMENT2)); 

	 //fprintf(stderr, "a_index: %d\n", a_index);
	 //fprintf(stderr, "struct: %d\n", (sizeof(RFC_TYPE_ELEMENT2)));
	 //fprintf(stderr, "mallocd: %d\n", ((a_index+1)*sizeof(RFC_TYPE_ELEMENT2)));

	 //fprintf(stderr, "adding fields into structure ...\n");
	 for (i=0; i <= a_index; i++) {
	   hash = (HV*) SvRV(*av_fetch(data, i, FALSE));
     type2[i].name = make_strdup(*hv_fetch(hash, (char *) "fieldname", 9, FALSE));
		 //fprintf(stderr, "fieldname: %s\n", type2[i].name);
     type2[i].length = SvIV(*hv_fetch(hash, (char *) "len1", 4, FALSE));
		 rfc_type_c = *(SvPV(*hv_fetch(hash, (char *) "exid", 4, FALSE), PL_na));
		 rc = RfcExidToRfcType(rfc_type_c, &rfc_type);
		 if (rc != RFC_OK) {
			 fprintf(stderr, "RFC Type conversion failed!\n");
			 exit(-1);
		 }
     type2[i].type = rfc_type;
     type2[i].decimals = SvIV(*hv_fetch(hash, (char *) "dec", 3, FALSE));
     type2[i].offset = SvIV(*hv_fetch(hash, (char *) "off1", 4, FALSE));
   }

	 //fprintf(stderr, "InstallStructure2 ...\n");
   rc = RfcInstallStructure2(name,
                             type2,
                             a_index + 1,
                             &type_handle);
	 //fprintf(stderr, "free name ...\n");
   free(name);
	 //fprintf(stderr, "free field names ...\n");
	 for (i=0; i <= a_index; i++) {
	   free(type2[i].name);
	 }
	 //fprintf(stderr, "free struct ...\n");
   free(type2);

   /* check the return code - if necessary construct an error message */
   if ( rc != RFC_OK ){
       RfcLastErrorEx( &error_info );
     if (( rc == RFC_EXCEPTION ) ||
         ( rc == RFC_SYS_EXCEPTION )) {
	     sprintf(errstr, "GROUP\t%d\tKEY\t%s\tMESSAGE\t%s", error_info.group, error_info.key, error_info.message );
     } else {
	     sprintf(errstr, "EXCEPT\t%s\tGROUP\t%d\tKEY\t%s\tMESSAGE\t%s", "RfcCallReceive", error_info.group, error_info.key, error_info.message);
     };
		 fprintf(stderr,"%s", errstr);
		 exit(-1);
   };

	 //fprintf(stderr, "RETURN handle %d ...\n", type_handle);
   return newSViv(type_handle);
#endif
}


/* build the RFC call interface, do the RFC call, and then build a complex
  hash structure of the results to pass back into perl */
SV* MyRfcPing(SV* sv_handle){

  RFC_HANDLE         handle;
  RFC_RC             rc;
  SAP_UC *           exception;

  handle = SvIV( sv_handle );
	rc = RfcCallReceive(handle, cU("RFC_PING"),
	                    NULL,
	                    NULL,
	                    NULL,
				              &exception );

   /* check the return code - if necessary construct an error message */

  if ( rc == RFC_OK ){
		 return newSViv(1);
  } else {
		 return newSViv(0);
  }
}


/* build the RFC call interface, do the RFC call, and then build a complex
  hash structure of the results to pass back into ruby */
SV* MySysinfo(SV* sv_handle){

   RFC_PARAMETER      myexports[MAX_PARA];
   RFC_PARAMETER      myimports[MAX_PARA];
   RFC_TABLE          mytables[MAX_PARA];
   RFC_RC             rc;
   RFC_HANDLE         handle;
   SAP_UC *           exception;
#ifdef SAPwithUNICODE
	 SAP_UC             errstr[2048];
	 SAP_UC             rfcsi[400];
#else
	 SAP_UC             errstr[1024];
	 SAP_UC             rfcsi[200];
#endif
   RFC_ERROR_INFO_EX  error_info;

   int                tab_cnt, 
                      imp_cnt,
                      exp_cnt;
   SV * sv_rfcsi;
	 
   handle = SvIV( sv_handle );

   tab_cnt = 0;
   exp_cnt = 0;
   imp_cnt = 0;

	 myimports[imp_cnt].name = cU("RFCSI_EXPORT");
	 myimports[imp_cnt].nlen = 12;
	 myimports[imp_cnt].type = handleOfRFCSI;
	 myimports[imp_cnt].addr = rfcsi;
	 myimports[imp_cnt].leng = sizeof(rfcsi);
   imp_cnt++;
	 //fprintf(stderr, "sizeof rfcsi is: %d\n", sizeof(rfcsi));
	 memset(rfcsi, 0, sizeof(rfcsi));

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

   rc =  RfcCallReceive( handle, cU("RFC_SYSTEM_INFO"),
				    myexports,
				    myimports,
				    mytables,
				    &exception );

   /* check the return code - if necessary construct an error message */
   if ( rc != RFC_OK ){
       RfcLastErrorEx( &error_info );
     if (( rc == RFC_EXCEPTION ) ||
         ( rc == RFC_SYS_EXCEPTION )) {
	     sprintfU(errstr, cU("EXCEPT\t%s\tGROUP\t%d\tKEY\t%s\tMESSAGE\t%s"), exception, error_info.group, error_info.key, error_info.message );
     } else {
	     sprintfU(errstr, cU("EXCEPT\t%s\tGROUP\t%d\tKEY\t%s\tMESSAGE\t%s"),cU("RfcCallReceive"), error_info.group, error_info.key, error_info.message);
     };
		 fprintfU(stderr,cU("%s"), errstr);
		 exit(-1);
   };

#ifdef SAPwithUNICODE
   sv_rfcsi = u16to8(myimports[0].addr, myimports[0].leng);
#else
   sv_rfcsi = newSVpvn(myimports[0].addr, myimports[0].leng);
#endif
	 
   /* free up the used memory for export parameters */
   for (imp_cnt = 0; imp_cnt < MAX_PARA; imp_cnt++){
       if ( myexports[imp_cnt].name == NULL ){
	       break;
       };
       myimports[imp_cnt].name = NULL;
       myimports[imp_cnt].nlen = 0;
       myimports[imp_cnt].leng = 0;
       myimports[imp_cnt].type = 0;
       myimports[imp_cnt].addr = NULL;
   };

	 return sv_rfcsi;
}


/* build the RFC call interface, do the RFC call, and then build a complex
  hash structure of the results to pass back into ruby */
SV* MyGetInterface(SV* sv_handle, SV* sv_function){

   RFC_RC             rc;
   RFC_HANDLE         handle;
   SAP_UC *           exception;
	 SAP_UC             errstr[1024];
   RFC_ERROR_INFO_EX  error_info;
	 char *							ptr;

   int                irow;
   //RFC_FUNINT *tParameters;
   RFC_U_FUNINT *tParameters;
	 ITAB_H i_tabh;

   AV*                array;
   HV*                hash;


	 //fprintf(stderr, "Get structure...\n");
   handle = SvIV( sv_handle );

#ifdef SAPwithUNICODE
   ptr = u8to16(sv_function);
#else
   ptr = make_strdup(sv_function);
#endif

   rc =  RfcGetFunctionInfoAsTable( handle, 
				    (SAP_CHAR *) ptr,
				    &i_tabh,
				    &exception );
   free(ptr);
	 /* check the return code - if necessary construct an error message */
   if ( rc != RFC_OK ){
       RfcLastErrorEx( &error_info );
     if (( rc == RFC_EXCEPTION ) ||
         ( rc == RFC_SYS_EXCEPTION )) {
	     sprintfU(errstr, cU("EXCEPT\t%s\tGROUP\t%d\tKEY\t%s\tMESSAGE\t%s"), exception, error_info.group, error_info.key, error_info.message );
     } else {
	     sprintfU(errstr, cU("EXCEPT\t%s\tGROUP\t%d\tKEY\t%s\tMESSAGE\t%s"),cU("RfcGetFunctionInfoAsTable"), error_info.group, error_info.key, error_info.message);
     };
		 fprintfU(stderr,cU("%s"), errstr);
		 exit(-1);
   };

	 array = newAV();
   for (irow = 1; irow <=  ItFill(i_tabh); irow++){
       tParameters = ItGetLine(i_tabh, irow);
       hash = newHV();
#ifdef SAPwithUNICODE
	     hv_store(hash, "paramclass", 10, u16to8((char *)tParameters->Paramclass, 2), 0);
	     hv_store(hash, "parameter", 9, u16to8((char *)tParameters->Parameter, 60), 0);
	     hv_store(hash, "tabname", 7, u16to8((char *)tParameters->Tabname, 60), 0);
	     hv_store(hash, "fieldname", 9, u16to8((char *)tParameters->Fieldname, 60), 0);
	     hv_store(hash, "exid", 4, u16to8((char *)tParameters->Exid, 2), 0);
	     hv_store(hash, "pos", 3, newSViv(tParameters->Position), 0);
	     //hv_store(hash, "off", 3, newSViv(tParameters->Offset), 0);
	     //hv_store(hash, "len", 3, newSViv(tParameters->Intlength), 0);
	     hv_store(hash, "dec", 3, newSViv(tParameters->Decimals), 0);
	     hv_store(hash, "off1", 4, newSViv(tParameters->Offset_b1), 0);
	     hv_store(hash, "len1", 4, newSViv(tParameters->Length_b1), 0);
	     hv_store(hash, "off2", 4, newSViv(tParameters->Offset_b2), 0);
	     hv_store(hash, "len2", 4, newSViv(tParameters->Length_b2), 0);
	     hv_store(hash, "off4", 4, newSViv(tParameters->Offset_b4), 0);
	     hv_store(hash, "len4", 4, newSViv(tParameters->Length_b4), 0);
	     hv_store(hash, "default", 6, u16to8((char *)tParameters->Default, 42), 0);
	     hv_store(hash, "text", 4, u16to8((char *)tParameters->Paramtext, 158), 0);
	     hv_store(hash, "opt", 3, u16to8((char *)tParameters->Optional, 2), 0);
#else
	     hv_store(hash, "paramclass", 10, newSVpv((char *)tParameters->Paramclass, 1), 0);
	     hv_store(hash, "parameter", 9, newSVpv((char *)tParameters->Parameter, 30), 0);
	     hv_store(hash, "tabname", 7, newSVpv((char *)tParameters->Tabname, 30), 0);
	     hv_store(hash, "fieldname", 9, newSVpv((char *)tParameters->Fieldname, 30), 0);
	     hv_store(hash, "exid", 4, newSVpv((char *)tParameters->Exid, 1), 0);
	     hv_store(hash, "pos", 3, newSViv(tParameters->Position), 0);
	     //hv_store(hash, "off", 3, newSViv(tParameters->Offset), 0);
	     //hv_store(hash, "len", 3, newSViv(tParameters->Intlength), 0);
	     hv_store(hash, "off1", 4, newSViv(tParameters->Offset_b1), 0);
	     hv_store(hash, "len1", 4, newSViv(tParameters->Length_b1), 0);
	     hv_store(hash, "off2", 4, newSViv(tParameters->Offset_b2), 0);
	     hv_store(hash, "len2", 4, newSViv(tParameters->Length_b2), 0);
	     hv_store(hash, "off4", 4, newSViv(tParameters->Offset_b4), 0);
	     hv_store(hash, "len4", 4, newSViv(tParameters->Length_b4), 0);
	     hv_store(hash, "dec", 3, newSViv(tParameters->Decimals), 0);
	     hv_store(hash, "default", 6, newSVpv((char *)tParameters->Default, 21), 0);
	     hv_store(hash, "text", 4, newSVpv((char *)tParameters->Paramtext, 79), 0);
	     hv_store(hash, "opt", 3, newSVpv((char *)tParameters->Optional, 1), 0);
#endif
	     av_push(array, newRV_noinc( (SV*) hash));
   };
   ItFree(i_tabh);

	 return newRV_noinc((SV*) array);
}



/* build the RFC call interface, do the RFC call, and then build a complex
  hash structure of the results to pass back into perl */
SV* MyRfcCallReceive(SV* sv_handle, SV* sv_function, SV* iface){

   RFC_PARAMETER      myexports[MAX_PARA];
   RFC_PARAMETER      myimports[MAX_PARA];
   RFC_TABLE          mytables[MAX_PARA];
   RFC_RC             rc;
   RFC_HANDLE         handle;
   SAP_UC *           function;
   SAP_UC *           exception;
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
#ifdef SAPwithUNICODE
   int                data_index,
                      k,
                      fsize,
                      itype;
   char *             ptr;
   char *             rowptr;
   AV*                av_data;
   AV*                av_field;
   AV*                av_fields;
   SV*                sv_value;
   SV*                sv_temp;
   SV*                sv_name;
#endif

   HV*                hash = newHV();


   tab_cnt = 0;
   exp_cnt = 0;
   imp_cnt = 0;

	 //fprintfU(stderr, cU("MyCallReceive\n"));
   handle = SvIV( sv_handle );
#ifdef SAPwithUNICODE
   function = (SAP_UC *) u8to16(sv_function);
	 //fprintfU(stderr, cU("function name: %s#%d\n"), function, SvCUR(sv_function));
#else
   function = SvPV( sv_function, SvCUR(sv_function) );
#endif

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
	     myimports[imp_cnt].leng = SvIV( *hv_fetch( p_hash, (char *) "LEN", 3, FALSE ) );
	     myimports[imp_cnt].type = SvIV( *hv_fetch( p_hash, (char *) "INTYPE", 6, FALSE ) );
	     myimports[imp_cnt].nlen = SvCUR(h_key);
#ifdef SAPwithUNICODE
	     myimports[imp_cnt].name = (SAP_UC *) u8to16( h_key );
			 //fprintfU(stderr, cU("import name: %s# length:%d\n"), myimports[imp_cnt].name, myimports[imp_cnt].leng);
			 //fprintf(stderr, "parameter type: %d\n", myimports[imp_cnt].type);
			 if (myimports[imp_cnt].type == RFCTYPE_CHAR ||
			     myimports[imp_cnt].type == RFCTYPE_BYTE ||
			     myimports[imp_cnt].type == RFCTYPE_NUM ||
			     myimports[imp_cnt].type == RFCTYPE_DATE ||
			     myimports[imp_cnt].type == RFCTYPE_TIME){
	       myimports[imp_cnt].addr = make_space2(myimports[imp_cnt].leng*2);
	       myimports[imp_cnt].leng = SvIV( *hv_fetch( p_hash, (char *) "LEN", 3, FALSE ) ) * 2;
			 } else {
	       myimports[imp_cnt].addr = make_space(*hv_fetch(p_hash, (char *) "LEN", 3, FALSE));
			 }
#else
	     myimports[imp_cnt].name = make_strdup( h_key );
	     myimports[imp_cnt].addr = make_space( *hv_fetch(p_hash, (char *) "LEN", 3, FALSE) );
#endif
	     ++imp_cnt;
	     break;

	   case RFCEXPORT:
	     /* build an export parameter and pass the value onto the structure */
	     myexports[exp_cnt].nlen = SvCUR(h_key);
	     myexports[exp_cnt].type = SvIV( *hv_fetch( p_hash, (char *) "INTYPE", 6, FALSE ) );
	     myexports[exp_cnt].leng = SvIV( *hv_fetch( p_hash, (char *) "LEN", 3, FALSE ) );
#ifdef SAPwithUNICODE
	     myexports[exp_cnt].name = (SAP_UC *) u8to16( h_key );
			 //fprintfU(stderr, cU("export name: %s#\n"), myexports[exp_cnt].name);
			 //fprintf(stderr, "parameter length: %d\n", myexports[exp_cnt].leng);
			 //fprintf(stderr, "parameter type: %d\n", myexports[exp_cnt].type);
			 if (hv_exists(p_hash, (char *) "DATA", 4)&& SvTRUE((SV *) *hv_fetch(p_hash, (char *) "DATA", 4, FALSE))) {
	       av_data = (AV*) SvRV(*hv_fetch(p_hash, (char *) "DATA", 4, FALSE));
	       av_fields = (AV*) SvRV(*hv_fetch(p_hash, (char *) "VALUE", 5, FALSE));
	       a_index = av_len(av_data);
		     //fprintf(stderr, "Array has: %d\n", a_index);
	       myexports[exp_cnt].addr = make_space2(myexports[exp_cnt].leng);
	       for (j = 0; j <= a_index; j++) {
					 av_field = (AV*) SvRV(*av_fetch(av_data, j, FALSE));
			     itype = SvIV(*av_fetch(av_field, 0, FALSE));
			     //fprintf(stderr, "Field: %d type: %d offset: %d len: %d\n", j, itype, SvIV(*av_fetch(av_field, 1, FALSE)), SvIV(*av_fetch(av_field, 2, FALSE)));
	         sv_value = (SV*)*av_fetch(av_fields, j, FALSE);
			     if (itype == RFCTYPE_CHAR ||
			         itype == RFCTYPE_BYTE ||
			         itype == RFCTYPE_NUM ||
			         itype == RFCTYPE_DATE ||
			         itype == RFCTYPE_TIME){
	           memcpy((char *)myexports[exp_cnt].addr+(SvIV(*av_fetch(av_field, 1, FALSE))), (ptr = u8to16p(sv_value)), SvCUR(sv_value)*2);
						 free(ptr);
				   } else {
	           memcpy((char *)myexports[exp_cnt].addr+(SvIV(*av_fetch(av_field, 1, FALSE))), SvPV(sv_value, SvCUR(sv_value)), SvCUR(sv_value));
					 };
				 };
			 } else {
			   if (myexports[exp_cnt].type == RFCTYPE_CHAR ||
			       myexports[exp_cnt].type == RFCTYPE_BYTE ||
			       myexports[exp_cnt].type == RFCTYPE_NUM ||
			       myexports[exp_cnt].type == RFCTYPE_DATE ||
			       myexports[exp_cnt].type == RFCTYPE_TIME){
	         //fprintf(stderr, "value: %s\n", *hv_fetch(p_hash, (char *) "VALUE", 5, FALSE));
	         myexports[exp_cnt].leng = SvIV( *hv_fetch( p_hash, (char *) "LEN", 3, FALSE ) ) * 2;
	         myexports[exp_cnt].addr = u8to16l( *hv_fetch(p_hash, (char *) "VALUE", 5, FALSE), &fsize);
	         myexports[exp_cnt].leng = fsize;
		 //fprintf(stderr, "parameter length NOW: %d\n", myexports[exp_cnt].leng);
	         //fprintfU(stderr, cU("value: %s#\n"), myexports[exp_cnt].addr);
                 //for (k=0;k<myexports[exp_cnt].leng;k++){
	         //fprintf(stderr, "%x|", *((char *) myexports[exp_cnt].addr+k));
                 //}
	         //fprintf(stderr, "\n");
            
			   } else {
	         myexports[exp_cnt].addr = make_copy( *hv_fetch(p_hash, (char *) "VALUE", 5, FALSE),
				  	        *hv_fetch(p_hash, (char *) "LEN", 3, FALSE) );
			   }
			 }
#else
	     myexports[exp_cnt].name = make_strdup( h_key );
	     myexports[exp_cnt].addr = make_copy( *hv_fetch(p_hash, (char *) "VALUE", 5, FALSE),
					        *hv_fetch(p_hash, (char *) "LEN", 3, FALSE) );
#endif
	     ++exp_cnt;
	     break;

	   case RFCTABLE:
	     /* construct a table parameter and copy the table rows on to the table handle */
#ifdef SAPwithUNICODE
	     mytables[tab_cnt].name = (SAP_UC *) u8to16( h_key );
	     av_data = (AV*) SvRV(*hv_fetch(p_hash, (char *) "DATA", 4, FALSE));
	     av_fields = (AV*) SvRV(*hv_fetch(p_hash, (char *) "VALUE", 5, FALSE));
	     data_index = av_len(av_data);
		   //fprintf(stderr, "Array has: %d\n", data_index);
#else
	     mytables[tab_cnt].name = make_strdup( h_key );
#endif
	     mytables[tab_cnt].nlen = SvCUR(h_key);
	     mytables[tab_cnt].leng = SvIV( *hv_fetch( p_hash, (char *) "LEN", 3, FALSE ) );
       mytables[tab_cnt].itmode = RFC_ITMODE_BYREFERENCE;
       //mytables[tab_cnt].type = RFCTYPE_CHAR; 
       mytables[tab_cnt].type = SvIV( *hv_fetch( p_hash, (char *) "INTYPE", 6, FALSE ) );
			 //fprintfU(stderr, cU("table name: %s#\n"), mytables[tab_cnt].name);
			 //fprintf(stderr, "table length: %d\n", mytables[tab_cnt].leng);
	   /* maybe should be RFCTYPE_BYTE */
       mytables[tab_cnt].ithandle = ItCreate( mytables[tab_cnt].name,
			                              SvIV( *hv_fetch( p_hash, (char *) "LEN", 3, FALSE ) ), 0 , 0 );
	     if ( mytables[tab_cnt].ithandle == NULL )
	       return 0; 
	     array = (AV*) SvRV( *hv_fetch( p_hash, (char *) "VALUE", 5, FALSE ) );
	     a_index = av_len( array );
	     for (j = 0; j <= a_index; j++) {
#ifdef SAPwithUNICODE
	       av_fields = (AV*) SvRV(*av_fetch( array, j, FALSE ));
				 //fprintf(stderr, "av_fields: %d\n", av_len(av_fields));
		     rowptr = ItAppLine(mytables[tab_cnt].ithandle);
	       for (k = 0; k <= data_index; k++) {
					 av_field = (AV*) SvRV(*av_fetch(av_data, k, FALSE));
			     itype = SvIV(*av_fetch(av_field, 0, FALSE));
			     //fprintf(stderr, "Field: %d type: %d offset: %d len: %d\n", k, itype, SvIV(*av_fetch(av_field, 1, FALSE)), SvIV(*av_fetch(av_field, 2, FALSE)));
	         sv_value = (SV*)*av_fetch(av_fields, k, FALSE);
			     if (itype == RFCTYPE_CHAR ||
			         itype == RFCTYPE_BYTE ||
			         itype == RFCTYPE_NUM ||
			         itype == RFCTYPE_DATE ||
			         itype == RFCTYPE_TIME){
	           memcpy((char *)rowptr+(SvIV(*av_fetch(av_field, 1, FALSE))), (ptr = u8to16p(sv_value)), SvCUR(sv_value)*2);
						 free(ptr);
				   } else {
	           memcpy((char *)rowptr+(SvIV(*av_fetch(av_field, 1, FALSE))), SvPV(sv_value, SvCUR(sv_value)), SvCUR(sv_value));
					 };
				 };
#else
	       Copy(  SvPV( *av_fetch( array, j, FALSE ), PL_na ),
		      ItAppLine( mytables[tab_cnt].ithandle ),
		      mytables[tab_cnt].leng,
		      char );
#endif
	     };
	     tab_cnt++;
	     break;

	   default:
	     fprintf(stderr, "    I DONT KNOW WHAT THIS PARAMETER IS: %s \n", SvPV(h_key, PL_na));
       exit(-1);
	     break;
     };

   };
       //exit(-1);

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
	 //fprintfU(stderr, cU("function name: %s# %d\n"), function, strlenU(function));
   rc =  RfcCallReceive( handle, function,
				    myexports,
				    myimports,
				    mytables,
				    &exception );
#ifdef SAPwithUNICODE
	 free(function);
#endif
 
	 //fprintf(stderr, "RFC call finished...\n");
   /* check the return code - if necessary construct an error message */
   if ( rc != RFC_OK ){
       RfcLastErrorEx( &error_info );
     if (( rc == RFC_EXCEPTION ) ||
         ( rc == RFC_SYS_EXCEPTION )) {
#ifdef SAPwithUNICODE
			 sv_temp = newSVpv("EXCEPT\t", 7);
	     sv_catsv(sv_temp, u16to8((char *)exception, strlenU(exception)*2));
	     sv_catpvn(sv_temp, "\tGROUP\t", 7);
	     sv_catsv(sv_temp, newSVpvf("%d", error_info.group));
	     sv_catpvn(sv_temp, "\tKEY\t", 5);
	     sv_catsv(sv_temp, u16to8((char *)error_info.key, strlenU(error_info.key)*2));
	     sv_catpvn(sv_temp, "\tMESSAGE\t", 9);
	     sv_catsv(sv_temp, u16to8((char *)error_info.message, strlenU(error_info.message)*2));
       hv_store(  hash, (char *) "__RETURN_CODE__", 15, sv_temp, 0 );
#else
       hv_store(  hash, (char *) "__RETURN_CODE__", 15,
		   newSVpvf( "EXCEPT\t%s\tGROUP\t%d\tKEY\t%s\tMESSAGE\t%s", exception, error_info.group, error_info.key, error_info.message ),
		  0 );
#endif
     } else {
#ifdef SAPwithUNICODE
			 sv_temp = newSVpv("EXCEPT\tRfcCallReceive", 21);
	     sv_catsv(sv_temp, u16to8((char *)exception, strlenU(exception)*2));
	     sv_catpvn(sv_temp, "\tGROUP\t", 7);
	     sv_catsv(sv_temp, newSVpvf("%d", error_info.group));
	     sv_catpvn(sv_temp, "\tKEY\t", 5);
	     sv_catsv(sv_temp, u16to8((char *)error_info.key, strlenU(error_info.key)*2));
	     sv_catpvn(sv_temp, "\tMESSAGE\t", 9);
	     sv_catsv(sv_temp, u16to8((char *)error_info.message, strlenU(error_info.message)*2));
       hv_store(  hash, (char *) "__RETURN_CODE__", 15, sv_temp, 0 );
#else
       hv_store(  hash, (char *) "__RETURN_CODE__", 15,
		   newSVpvf( "EXCEPT\t%s\tGROUP\t%d\tKEY\t%s\tMESSAGE\t%s","RfcCallReceive", error_info.group, error_info.key, error_info.message ),
		  0 );
#endif
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
#ifdef SAPwithUNICODE
			 sv_name = u16to8((char *) myimports[imp_cnt].name, myimports[imp_cnt].nlen * 2);
			 //fprintf(stderr, "the import name(out): %s#%d\n", SvPV(sv_name, SvCUR(sv_name)), SvCUR(sv_name));
			 //fprintf(stderr, "the import value length: %d \n", myimports[imp_cnt].leng);
	     p_hash = (HV*)SvRV(*hv_fetch(h_parms, SvPV(sv_name, SvCUR(sv_name)), SvCUR(sv_name), FALSE));
			 if (hv_exists(p_hash, (char *) "DATA", 4)&& SvTRUE((SV *) *hv_fetch(p_hash, (char *) "DATA", 4, FALSE))) {
	       av_data = (AV*) SvRV(*hv_fetch(p_hash, (char *) "DATA", 4, FALSE));
	       a_index = av_len(av_data);
		     //fprintf(stderr, "Array has: %d\n", a_index);
	       hv_store_ent(hash, sv_name, newRV_noinc((SV*) (av_fields = newAV())), 0);
	       for (j = 0; j <= a_index; j++) {
					 av_field = (AV*) SvRV(*av_fetch(av_data, j, FALSE));
			     itype = SvIV(*av_fetch(av_field, 0, FALSE));
			     //fprintf(stderr, "Field: %d type: %d offset: %d len: %d\n", j, itype, SvIV(*av_fetch(av_field, 1, FALSE)), SvIV(*av_fetch(av_field, 2, FALSE)));
			     if (itype == RFCTYPE_CHAR ||
			         itype == RFCTYPE_BYTE ||
			         itype == RFCTYPE_NUM ||
			         itype == RFCTYPE_DATE ||
			         itype == RFCTYPE_TIME){
	           av_push(av_fields, u16to8((char *)myimports[imp_cnt].addr+(SvIV(*av_fetch(av_field, 1, FALSE))), SvIV(*av_fetch(av_field, 2, FALSE))));
				   } else {
	           av_push(av_fields, newSVpv((char *)myimports[imp_cnt].addr+(SvIV(*av_fetch(av_field, 1, FALSE))), SvIV(*av_fetch(av_field, 2, FALSE))));
					 };
				 };
			 } else {
			   if (myimports[imp_cnt].type == RFCTYPE_CHAR ||
			       myimports[imp_cnt].type == RFCTYPE_BYTE ||
			       myimports[imp_cnt].type == RFCTYPE_NUM ||
			       myimports[imp_cnt].type == RFCTYPE_DATE ||
			       myimports[imp_cnt].type == RFCTYPE_TIME){
	         //fprintfU(stderr, cU("value: %s#\n"), myimports[imp_cnt].addr);
	         hv_store_ent(hash, sv_name, u16to8(myimports[imp_cnt].addr, myimports[imp_cnt].leng), 0);
			   } else {
	         hv_store_ent(hash, sv_name, newSVpv(myimports[imp_cnt].addr, myimports[imp_cnt].leng), 0);
			   }
			 }
#else
	     hv_store(  hash, myimports[imp_cnt].name, myimports[imp_cnt].nlen, newSVpv( myimports[imp_cnt].addr, myimports[imp_cnt].leng ), 0 );
#endif
       free(myimports[imp_cnt].name);
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
//#ifdef DOIBMWKRND
//	   hv_store(  hash, mytables[tab_cnt].name, mytables[tab_cnt].nlen, newRV_noinc( array = newAV() ), 0);
//#else
#ifdef SAPwithUNICODE
		 sv_name = u16to8((char *) mytables[tab_cnt].name, mytables[tab_cnt].nlen * 2);
		 //fprintf(stderr, "the table name(out): %s#%d\n", SvPV(sv_name, SvCUR(sv_name)), SvCUR(sv_name));
		 //fprintf(stderr, "the table value length: %d \n", mytables[tab_cnt].leng);
	   hv_store_ent(hash, sv_name, newRV_noinc( (SV*) ( array = newAV() ) ), 0);
	   p_hash = (HV*)SvRV(*hv_fetch(h_parms, SvPV(sv_name, SvCUR(sv_name)), SvCUR(sv_name), FALSE));
	   av_data = (AV*) SvRV(*hv_fetch(p_hash, (char *) "DATA", 4, FALSE));
	   a_index = av_len(av_data);
		 //fprintf(stderr, "Array has: %d\n", a_index);
#else
	   hv_store(hash, mytables[tab_cnt].name, mytables[tab_cnt].nlen, newRV_noinc((SV*) (array = newAV())), 0);
#endif
//#endif
	   /*  grab each table row and push onto an array */
	   for (irow = 1; irow <=  ItFill(mytables[tab_cnt].ithandle); irow++){
#ifdef SAPwithUNICODE
	       //av_push( array, u16to8( ItGetLine( mytables[tab_cnt].ithandle, irow ), mytables[tab_cnt].leng ) );
	       ptr = ItGetLine(mytables[tab_cnt].ithandle, irow);
	       av_push(array, newRV_noinc((SV*) (av_fields = newAV())));
	       for (j = 0; j <= a_index; j++) {
					 av_field = (AV*) SvRV(*av_fetch(av_data, j, FALSE));
					 itype = SvIV(*av_fetch(av_field, 0, FALSE));
					 //fprintf(stderr, "Field: %d type: %d offset: %d len: %d\n", j, itype, SvIV(*av_fetch(av_field, 1, FALSE)), SvIV(*av_fetch(av_field, 2, FALSE)));
			     if (itype == RFCTYPE_CHAR ||
			         itype == RFCTYPE_BYTE ||
			         itype == RFCTYPE_NUM ||
			         itype == RFCTYPE_DATE ||
			         itype == RFCTYPE_TIME){
	           av_push(av_fields, u16to8((char *)ptr+(SvIV(*av_fetch(av_field, 1, FALSE))), SvIV(*av_fetch(av_field, 2, FALSE))));
					 } else {
	           av_push(av_fields, newSVpv((char *)ptr+(SvIV(*av_fetch(av_field, 1, FALSE))), SvIV(*av_fetch(av_field, 2, FALSE))));
					 };
	       };
#else
	       av_push(array, newSVpv(ItGetLine(mytables[tab_cnt].ithandle, irow), mytables[tab_cnt].leng));
#endif
	   };
	   
	   free(mytables[tab_cnt].name);
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
#ifdef SAPwithUNICODE
      sprintfU(current_tid+0, cU("%s"), tid);
#else
      sprintf(current_tid+0, "%s", tid);
#endif
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
#ifdef SAPwithUNICODE
    XPUSHs(u16to8((char *)tid, strlenU(tid)*2));
#else
    XPUSHs( newSVpvf("%s",tid) );
#endif

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
#ifdef SAPwithUNICODE
    XPUSHs(u16to8((char *)tid, strlenU(tid)*2));
#else
    XPUSHs( newSVpvf("%s",tid) );
#endif

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
#ifdef SAPwithUNICODE
    XPUSHs(u16to8((char *)tid, strlenU(tid)*2));
#else
    XPUSHs( newSVpvf("%s",tid) );
#endif

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
#ifdef SAPwithUNICODE
	SV* sv_temp;
#endif


  rc = RfcGetName(handle, funcname);
  if (rc != RFC_OK)
  {
     /* fprintf(stderr, "RFC connection failure code: %d \n", rc); */
     /* hv_store(p_saprfc, (char *) "ERROR", 5, newSVpvf("RFC connection failure code: %d", rc), 0); */
       return rc;
  }

  /* check at this point for registered functions */
#ifdef SAPwithUNICODE
	sv_temp = u16to8((char *) funcname, strlenU(funcname) * 2);
  if ( ! hv_exists(p_iface_hash, SvPV(sv_temp, PL_na), SvCUR(sv_temp)) ){
#else
  if ( ! hv_exists(p_iface_hash, funcname, strlen(funcname)) ){
#endif
       /* fprintf(stderr, "the MISSING Function Name is: %s\n", funcname); */
       RfcRaise( handle, cU("FUNCTION_MISSING") );
       /* do event callback to intertwine other events */
       /* rc = loop_callback(sv_callback, sv_saprfc); */
       /* XXX   */
       return RFC_NOT_FOUND;
  }

  /* pass in the interface to be handled */
#ifdef SAPwithUNICODE
  sv_iface = *hv_fetch(p_iface_hash, SvPV(sv_temp, PL_na), SvCUR(sv_temp), FALSE);
#else
  sv_iface = *hv_fetch(p_iface_hash, funcname, strlen(funcname), FALSE);
#endif

  handle_request(handle, sv_iface);

  rc = loop_callback(sv_callback, global_saprfc);

  return rc;
}

#undef  NL
#define NL cU("\n")

static SAP_UC *user_global_server_docu(void)
{
  static SAP_UC docu[] =
  cU("The RFC library will call this function if any unknown")            NL
  cU("RFC function should be executed in this RFC server program.")       NL
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
#ifdef SAPwithUNICODE
	 SV* sv_temp;
   char * conn_ptr = NULL;
   char * gwserv = NULL;
   char * gwhost = NULL;
   char * tpname = NULL;
#else
   char gwserv[8];
#endif

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

#ifdef SAPwithUNICODE
   conn_ptr =  u8to16(sv_conn);
   handle = RfcAcceptExt( (SAP_UC *) conn_ptr );
   free(conn_ptr);
#else
   handle = RfcAcceptExt( SvPV(sv_conn, SvCUR(sv_conn)) );
#endif

   /* fprintf(stderr, "what is my handle: %d\n", handle); */
#ifdef SAPwithUNICODE
   rc = RfcCheckRegisterServer( (SAP_UC *)(tpname = u8to16((SV*) *hv_fetch(p_saprfc, (char *) "TPNAME", 6, FALSE))),
                                (SAP_UC *)(gwhost = u8to16((SV*) *hv_fetch(p_saprfc, (char *) "GWHOST", 6, FALSE))), 
                                (SAP_UC *)(gwserv = u8to16((SV*) *hv_fetch(p_saprfc, (char *) "GWSERV", 6, FALSE))), 
 			        &ntotal, &ninit, &nready, &nbusy, &error_info);
	 free(tpname);
	 free(gwhost);
	 free(gwserv);
#else
   sprintf(gwserv, "%d", (int)(SvIV((SV*) *hv_fetch(p_saprfc, (char *) "GWSERV", 6, FALSE)))); 
   rc = RfcCheckRegisterServer( SvPV((SV*) *hv_fetch(p_saprfc, (char *) "TPNAME", 6, FALSE), PL_na),
                                SvPV((SV*) *hv_fetch(p_saprfc, (char *) "GWHOST", 6, FALSE), PL_na), 
 			        gwserv, 
 			        &ntotal, &ninit, &nready, &nbusy, &error_info);
#endif

   if (rc != RFC_OK)
   {
     /*
     fprintf(stderr, "\nGroup       Error group %d\n", error_info.group);
     fprintf(stderr, "Key         %s\n", error_info.key);
     fprintf(stderr, "Message     %s\n\n", error_info.message);
     */
#ifdef SAPwithUNICODE
     hv_store(p_saprfc, (char *) "ERROR", 5, 
        newSVpvf("\nGroup       Error group %d\nKey         %s\nMessage     %s\n\n", 
	           error_info.group, SvPV(u16to8((char *)error_info.key, strlenU(error_info.key)*2), PL_na), SvPV(u16to8((char *)error_info.message, strlenU(error_info.message)*2), PL_na)), 0);
#else
     hv_store(p_saprfc, (char *) "ERROR", 5, 
        newSVpvf("\nGroup       Error group %d\nKey         %s\nMessage     %s\n\n", 
	           error_info.group, error_info.key, error_info.message), 0);
#endif
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
     RfcAbort( handle, cU("Initialisation error"));
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
           /* fprintf(stderr, "\nERROR: Install %s     rfc_rc = %d",
	                   name_user_global_server, rc); */
           RfcAbort( handle, cU("Cant install global tRFC handler") );
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
#ifdef SAPwithUNICODE
	sv_temp = u16to8((char *) funcname, strlenU(funcname) * 2);
  if ( ! hv_exists(p_iface_hash, SvPV(sv_temp, PL_na), SvCUR(sv_temp)) ){
#else
     if ( ! hv_exists(p_iface_hash, funcname, strlen(funcname)) ){
#endif
       /* fprintf(stderr, "the MISSING Function Name is: %s\n", funcname); */
       RfcRaise( handle, cU("FUNCTION_MISSING") );
       /* do event callback to intertwine other events */
       rc = loop_callback(sv_callback, sv_saprfc);
       continue;
     }

     /* pass in the interface to be handled */
#ifdef SAPwithUNICODE
     sv_iface = *hv_fetch(p_iface_hash, SvPV(sv_temp, PL_na), SvCUR(sv_temp), FALSE);
#else
     sv_iface = *hv_fetch(p_iface_hash, funcname, strlen(funcname), FALSE);
#endif

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



SV* my_register( SV* sv_conn, SV* sv_docu, SV* sv_ifaces, SV* sv_saprfc )
{
   /* initialized data */
   static RFC_ENV    env;
   RFC_ERROR_INFO_EX  error_info;
   RFC_HANDLE handle;
   RFC_RC     rc;
   SV* sv_is_trfc;
   RFC_INT ntotal,
           ninit,
           nready,
           nbusy;
#ifdef SAPwithUNICODE
   char * conn_ptr = NULL;
   char * gwserv = NULL;
   char * gwhost = NULL;
   char * tpname = NULL;
#else
   char gwserv[8];
#endif

   /*
    * install error handler
    */
   memset(current_tid, 0, sizeof(current_tid));
   global_saprfc = newSVsv(sv_saprfc);
   p_saprfc = (HV*)SvRV( global_saprfc );

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

#ifdef SAPwithUNICODE
   conn_ptr =  u8to16(sv_conn);
   handle = RfcAcceptExt( (SAP_UC *) conn_ptr );
   free(conn_ptr);
#else
   handle = RfcAcceptExt( SvPV(sv_conn, SvCUR(sv_conn)) );
#endif

   /* fprintf(stderr, "what is my handle: %d\n", handle); */
#ifdef SAPwithUNICODE
   rc = RfcCheckRegisterServer( (SAP_UC *)(tpname = u8to16((SV*) *hv_fetch(p_saprfc, (char *) "TPNAME", 6, FALSE))),
                                (SAP_UC *)(gwhost = u8to16((SV*) *hv_fetch(p_saprfc, (char *) "GWHOST", 6, FALSE))), 
                                (SAP_UC *)(gwserv = u8to16((SV*) *hv_fetch(p_saprfc, (char *) "GWSERV", 6, FALSE))), 
 			        &ntotal, &ninit, &nready, &nbusy, &error_info);
	 free(tpname);
	 free(gwhost);
	 free(gwserv);
#else
   sprintf(gwserv, "%d", (int)(SvIV((SV*) *hv_fetch(p_saprfc, (char *) "GWSERV", 6, FALSE)))); 
   rc = RfcCheckRegisterServer( SvPV((SV*) *hv_fetch(p_saprfc, (char *) "TPNAME", 6, FALSE), PL_na),
                                SvPV((SV*) *hv_fetch(p_saprfc, (char *) "GWHOST", 6, FALSE), PL_na), 
 			        gwserv, 
 			        &ntotal, &ninit, &nready, &nbusy, &error_info);
#endif

   if (rc != RFC_OK)
   {
#ifdef SAPwithUNICODE
     hv_store(p_saprfc, (char *) "ERROR", 5, 
        newSVpvf("\nGroup       Error group %d\nKey         %s\nMessage     %s\n\n", 
	           error_info.group, SvPV(u16to8((char *)error_info.key, strlenU(error_info.key)*2), PL_na), SvPV(u16to8((char *)error_info.message, strlenU(error_info.message)*2), PL_na)), 0);
#else
     hv_store(p_saprfc, (char *) "ERROR", 5, 
        newSVpvf("\nGroup       Error group %d\nKey         %s\nMessage     %s\n\n", 
	           error_info.group, error_info.key, error_info.message), 0);
#endif
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
   sv_store_docu = newSVsv(sv_docu);

   rc = install_docu(handle);

   if( rc != RFC_OK )
   {
     RfcAbort( handle, cU("Initialisation error"));
     hv_store(p_saprfc, (char *) "ERROR", 5, newSVpvf("Initialisation error in the gateway"), 0);
     return newSViv(-1);
   }

	 global_sv_ifaces = newSVsv(sv_ifaces);

    /* global handler for tRFC  */
    if (SvTRUE(sv_is_trfc)) {
        rc = RfcInstallFunction(name_user_global_server,
                             (RFC_ONCALL) user_global_server,
	                      user_global_server_docu());
       if( rc != RFC_OK )
       {
           /* fprintf(stderr, "\nERROR: Install %s     rfc_rc = %d",
	                   name_user_global_server, rc); */
           RfcAbort( handle, cU("Cant install global tRFC handler"));
           return newSViv(-1);
       }
    }

   return newSViv((int) handle);
} 



SV* my_one_loop(SV* sv_handle, SV* sv_wait)
{
   /* initialized data */
   RFC_HANDLE handle;
   RFC_RC     rc;
   RFC_FUNCTIONNAME funcname;
   SV* sv_iface;
   SV* sv_is_trfc;
   RFC_INT wtime = 0; 
#ifdef SAPwithUNICODE
	 SV* sv_temp;
#endif


   p_iface_hash = (HV*)SvRV( global_sv_ifaces );
   p_saprfc = (HV*)SvRV( global_saprfc );
   /*
    *  Setup the wait value
    *
    */

   /* get the tRFC indicator  */
   handle = SvIV( sv_handle );
   sv_is_trfc = (SV*) *hv_fetch(p_saprfc, (char *) "TRFC", 4, FALSE); 
   sv_callback = *hv_fetch(p_saprfc, (char *) "CALLBACK", 8, FALSE);
   if (SvTRUE(sv_wait))
      wtime = SvIV(sv_wait);
   else
      wtime = RFC_WAIT_TIME;
   
   
   /* fprintf(stderr, "The Wait time is: %d \n", wtime);  */

   /* fprintf(stderr, "going to wait ...\n");  */
   rc = RfcWaitForRequest(handle, wtime);
   /* fprintf(stderr, "done the wait: %d \n", rc);  */

   /* needs to get an RFC_OK or RFC_RETRY */
   if (rc == RFC_RETRY){
     /*  do event loop callback here for interloop breakout */
     /* fprintf(stderr, "got into the retry...\n"); */
     rc = loop_callback(sv_callback, global_saprfc);
     return newSViv(rc);
   }

   /* short circuit here for tRFC  */
   if (SvTRUE(sv_is_trfc)) {
       rc = RfcDispatch(handle);
       /* fprintf(stderr, "done the dispatch: %d \n", rc);  */
       return newSViv(rc);
   }

   /* this will block until a straight RFC call is made */
   if (rc == RFC_OK)
     rc = RfcGetName(handle, funcname);
   /* fprintf(stderr, "Got the function(%d): %s ...\n", rc, funcname); */

   if (rc != RFC_OK){
     /* fprintf(stderr, "RFC connection failure code: %d \n", rc); */
     hv_store(p_saprfc, (char *) "ERROR", 5, newSVpvf("RFC connection failure code: %d", rc), 0);
     return newSViv(rc);
   }

   /* check at this point for registered functions */
#ifdef SAPwithUNICODE
	sv_temp = u16to8((char *) funcname, strlenU(funcname) * 2);
  if ( ! hv_exists(p_iface_hash, SvPV(sv_temp, PL_na), SvCUR(sv_temp)) ){
#else
   if ( ! hv_exists(p_iface_hash, funcname, strlen(funcname)) ){
#endif
     /* fprintf(stderr, "the MISSING Function Name is: %s\n", funcname); */
     RfcRaise( handle, cU("FUNCTION_MISSING") );
     /* do event callback to intertwine other events */
     rc = loop_callback(sv_callback, global_saprfc);
     return newSViv(rc);
   }

	 /* fprintf(stderr, "looked up the iface...\n"); */

   /* pass in the interface to be handled */
#ifdef SAPwithUNICODE
   sv_iface = *hv_fetch(p_iface_hash, SvPV(sv_temp, PL_na), SvCUR(sv_temp), FALSE);
#else
   sv_iface = *hv_fetch(p_iface_hash, funcname, strlen(funcname), FALSE);
#endif
   /* fprintf(stderr, "Got the function: %s ...\n", funcname); */


   handle_request(handle, sv_iface);

   /* fprintf(stderr, "round the loop ...\n"); */

  return newSViv(rc);
}



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
   rc = RfcInstallFunction(cU("RFC_DOCU"),
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

#ifdef SAPwithUNICODE
  hv_store(hv_sysinfo, "dest", 4, u16to8((char *)rfc_attributes.dest, strlenU(rfc_attributes.dest)*2), 0);
  hv_store(hv_sysinfo, "localhost", 9, u16to8((char *)rfc_attributes.own_host, strlenU(rfc_attributes.own_host)*2), 0);
  if (rfc_attributes.rfc_role == RFC_ROLE_CLIENT)
  {
    if (rfc_attributes.partner_type == RFC_SERVER_EXT)
      hv_store(hv_sysinfo, "servprogname", 12, u16to8((char *)rfc_attributes.partner_host, strlenU(rfc_attributes.partner_host)*2), 0);
    else if (rfc_attributes.partner_type == RFC_SERVER_EXT_REG)
      hv_store(hv_sysinfo, "servprogid", 10, u16to8((char *)rfc_attributes.partner_host, strlenU(rfc_attributes.partner_host)*2), 0);
    else
      hv_store(hv_sysinfo, "partnerhost", 11, u16to8((char *)rfc_attributes.partner_host, strlenU(rfc_attributes.partner_host)*2), 0);
  }
  else
    hv_store(hv_sysinfo, "partnerhost", 11, u16to8((char *)rfc_attributes.partner_host, strlenU(rfc_attributes.partner_host)*2), 0);

  hv_store(hv_sysinfo, "sysnr", 5, u16to8((char *)rfc_attributes.systnr, strlenU(rfc_attributes.systnr)*2), 0);
  hv_store(hv_sysinfo, "sysid", 5, u16to8((char *)rfc_attributes.sysid, strlenU(rfc_attributes.sysid)*2), 0);
  hv_store(hv_sysinfo, "mandt", 5, u16to8((char *)rfc_attributes.client, strlenU(rfc_attributes.client)*2), 0);
  hv_store(hv_sysinfo, "user", 4, u16to8((char *)rfc_attributes.user, strlenU(rfc_attributes.user)*2), 0);
  hv_store(hv_sysinfo, "lang", 4, u16to8((char *)rfc_attributes.language, strlenU(rfc_attributes.language)*2), 0);
  hv_store(hv_sysinfo, "isolang", 7, u16to8((char *)rfc_attributes.ISO_language, strlenU(rfc_attributes.ISO_language)*2), 0);
  if (rfc_attributes.trace == 'X')
       hv_store(hv_sysinfo, "trace", 5, newSVpv("ON", 2), 0);
  else
       hv_store(hv_sysinfo, "trace", 5, newSVpv("OFF", 3), 0);

  hv_store(hv_sysinfo, "localcodepage", 13, u16to8((char *)rfc_attributes.own_codepage, strlenU(rfc_attributes.own_codepage)*2), 0);
  hv_store(hv_sysinfo, "partnercodepage", 15, u16to8((char *)rfc_attributes.partner_codepage, strlenU(rfc_attributes.partner_codepage)*2), 0);
  if (rfc_attributes.rfc_role == RFC_ROLE_CLIENT)
    hv_store(hv_sysinfo, "rfcrole", 7, newSVpv("External RFC Client", strlen("External RFC Client")), 0);
  else if (rfc_attributes.own_type == RFC_SERVER_EXT)
    hv_store(hv_sysinfo, "rfcrole", 7, newSVpv("External RFC Server, started by SAP gateway", strlen("External RFC Server, started by SAP gateway")), 0);
  else
    hv_store(hv_sysinfo, "rfcrole", 7, newSVpv("External RFC Server, registered at SAP gateway", strlen("External RFC Server, registered at SAP gateway")), 0);

  hv_store(hv_sysinfo, "rel", 3, u16to8((char *)rfc_attributes.own_rel, strlenU(rfc_attributes.own_rel)*2), 0);

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

  hv_store(hv_sysinfo, "partnerrel", 10, u16to8((char *)rfc_attributes.partner_rel, strlenU(rfc_attributes.partner_rel)*2), 0);
  hv_store(hv_sysinfo, "kernelrel", 9, u16to8((char *)rfc_attributes.kernel_rel, strlenU(rfc_attributes.kernel_rel)*2), 0);
  hv_store(hv_sysinfo, "convid", 6, u16to8((char *)rfc_attributes.CPIC_convid, strlenU(rfc_attributes.CPIC_convid)*2), 0);
#else
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
#endif

  return;
}


/*
 * Generic Inbound RFC Request Handler
 *
 */
static RFC_RC DLL_CALL_BACK_FUNCTION handle_request(  RFC_HANDLE handle, SV* sv_iface )
{
    RFC_PARAMETER parameter[MAX_PARA];
    RFC_TABLE     table[MAX_PARA];
    RFC_RC        rc;
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
#ifdef SAPwithUNICODE
   int                data_index,
                      k,
                      fsize,
                      itype;
   char *             ptr;
   char *             rowptr;
   AV*                av_data;
   AV*                av_field;
   AV*                av_fields;
   SV*                sv_value;
   SV*                sv_name;
#endif

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
#ifdef SAPwithUNICODE
	     parameter[imp_cnt].name = (SAP_UC *) u8to16( h_key );
	     parameter[imp_cnt].leng = SvIV( *hv_fetch( p_hash, (char *) "LEN", 3, FALSE ) );
	     parameter[imp_cnt].type = SvIV( *hv_fetch( p_hash, (char *) "INTYPE", 6, FALSE ) );
	     parameter[imp_cnt].nlen = strlen( SvPV(h_key, PL_na));
			 //fprintfU(stderr, cU("import name: %s# length:%d\n"), myimports[imp_cnt].name, myimports[imp_cnt].leng);
			 //fprintf(stderr, "parameter type: %d\n", myimports[imp_cnt].type);
			 if (parameter[imp_cnt].type == RFCTYPE_CHAR ||
			     parameter[imp_cnt].type == RFCTYPE_BYTE ||
			     parameter[imp_cnt].type == RFCTYPE_NUM ||
			     parameter[imp_cnt].type == RFCTYPE_DATE ||
			     parameter[imp_cnt].type == RFCTYPE_TIME){
	       parameter[imp_cnt].addr = make_space2(parameter[imp_cnt].leng*2);
	       parameter[imp_cnt].leng = SvIV( *hv_fetch( p_hash, (char *) "LEN", 3, FALSE ) ) * 2;
			 } else {
	       parameter[imp_cnt].addr = make_space2(parameter[imp_cnt].leng);
			 }
#else
	     parameter[imp_cnt].name = make_strdup( h_key );
	     if ( parameter[imp_cnt].name == NULL )
	       return 0;
	     parameter[imp_cnt].nlen = strlen( SvPV(h_key, PL_na));
	     parameter[imp_cnt].addr = make_space( *hv_fetch(p_hash, (char *) "LEN", 3, FALSE) );
	     parameter[imp_cnt].leng = SvIV( *hv_fetch( p_hash, (char *) "LEN", 3, FALSE ) );
	     parameter[imp_cnt].type = SvIV( *hv_fetch( p_hash, (char *) "INTYPE", 6, FALSE ) );
#endif
	     ++imp_cnt;
	     break;

	     case RFCTABLE:
	     /* construct a table parameter and copy the table rows on to the table handle */
           /* fprintf(stderr, "adding table parameter name is: %s\n", SvPV(h_key, PL_na)); */
#ifdef SAPwithUNICODE
	     table[tab_cnt].name = (SAP_UC *) u8to16( h_key );
#else
	     table[tab_cnt].name = make_strdup( h_key );
	     if ( table[tab_cnt].name == NULL )
	         return 0;
       //table[tab_cnt].type = RFCTYPE_CHAR; 
	     /* maybe should be RFCTYPE_BYTE */
#endif
	     table[tab_cnt].nlen = strlen( SvPV(h_key, PL_na));
	     table[tab_cnt].leng = SvIV( *hv_fetch( p_hash, (char *) "LEN", 3, FALSE ) );
       table[tab_cnt].itmode = RFC_ITMODE_BYREFERENCE;
       table[tab_cnt].type = SvIV( *hv_fetch( p_hash, (char *) "INTYPE", 6, FALSE ) );
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
#ifdef SAPwithUNICODE
			 sv_name = u16to8((char *) parameter[imp_cnt].name, parameter[imp_cnt].nlen * 2);
			 //fprintf(stderr, "the import name(out): %s#%d\n", SvPV(sv_name, SvCUR(sv_name)), SvCUR(sv_name));
			 //fprintf(stderr, "the import value length: %d \n", myimports[imp_cnt].leng);
	     p_hash = (HV*)SvRV(*hv_fetch(h_parms, SvPV(sv_name, SvCUR(sv_name)), SvCUR(sv_name), FALSE));
			 if (hv_exists(p_hash, (char *) "DATA", 4)&& SvTRUE((SV *) *hv_fetch(p_hash, (char *) "DATA", 4, FALSE))) {
	       av_data = (AV*) SvRV(*hv_fetch(p_hash, (char *) "DATA", 4, FALSE));
	       a_index = av_len(av_data);
		     //fprintf(stderr, "Array has: %d\n", a_index);
	       hv_store_ent(hash, sv_name, newRV_noinc((SV*) (av_fields = newAV())), 0);
	       for (j = 0; j <= a_index; j++) {
					 av_field = (AV*) SvRV(*av_fetch(av_data, j, FALSE));
			     itype = SvIV(*av_fetch(av_field, 0, FALSE));
			     //fprintf(stderr, "Field: %d type: %d offset: %d len: %d\n", j, itype, SvIV(*av_fetch(av_field, 1, FALSE)), SvIV(*av_fetch(av_field, 2, FALSE)));
			     if (itype == RFCTYPE_CHAR ||
			         itype == RFCTYPE_BYTE ||
			         itype == RFCTYPE_NUM ||
			         itype == RFCTYPE_DATE ||
			         itype == RFCTYPE_TIME){
	           av_push(av_fields, u16to8((char *)parameter[imp_cnt].addr+(SvIV(*av_fetch(av_field, 1, FALSE))), SvIV(*av_fetch(av_field, 2, FALSE))));
				   } else {
	           av_push(av_fields, newSVpv((char *)parameter[imp_cnt].addr+(SvIV(*av_fetch(av_field, 1, FALSE))), SvIV(*av_fetch(av_field, 2, FALSE))));
					 };
				 };
			 } else {
			   if (parameter[imp_cnt].type == RFCTYPE_CHAR ||
			       parameter[imp_cnt].type == RFCTYPE_BYTE ||
			       parameter[imp_cnt].type == RFCTYPE_NUM ||
			       parameter[imp_cnt].type == RFCTYPE_DATE ||
			       parameter[imp_cnt].type == RFCTYPE_TIME){
	         //fprintfU(stderr, cU("value: %s#\n"), myimports[imp_cnt].addr);
	         hv_store_ent(hash, sv_name, u16to8(parameter[imp_cnt].addr, parameter[imp_cnt].leng), 0);
			   } else {
	         hv_store_ent(hash, sv_name, newSVpv(parameter[imp_cnt].addr, parameter[imp_cnt].leng), 0);
			   }
			 }
#else
       /* fprintf(stderr, "getting import parameter: %s \n", parameter[imp_cnt].name); */
	     hv_store(  hash, parameter[imp_cnt].name, parameter[imp_cnt].nlen, newSVpv( parameter[imp_cnt].addr, parameter[imp_cnt].leng ), 0 );
       /* fprintf(stderr, " parameter value: %s \n", parameter[imp_cnt].addr); */
#endif
       Safefree(parameter[imp_cnt].name);
       parameter[imp_cnt].name = NULL;
       parameter[imp_cnt].nlen = 0;
       parameter[imp_cnt].leng = 0;
       parameter[imp_cnt].type = 0;
       if ( parameter[imp_cnt].addr != NULL ){
	       Safefree(parameter[imp_cnt].addr);
       };
       parameter[imp_cnt].addr = NULL;

    };
   
    /* retrieve the values of the table parameters and free up the memory */
    for (tab_cnt = 0; tab_cnt < MAX_PARA; tab_cnt++){
       if ( table[tab_cnt].name == NULL ){
	       break;
       };
#ifdef SAPwithUNICODE
		 sv_name = u16to8((char *) table[tab_cnt].name, table[tab_cnt].nlen * 2);
		 //fprintf(stderr, "the table name(out): %s#%d\n", SvPV(sv_name, SvCUR(sv_name)), SvCUR(sv_name));
		 //fprintf(stderr, "the table value length: %d \n", mytables[tab_cnt].leng);
	   hv_store_ent(hash, sv_name, newRV_noinc( (SV*) ( array = newAV() ) ), 0);
	   p_hash = (HV*)SvRV(*hv_fetch(h_parms, SvPV(sv_name, SvCUR(sv_name)), SvCUR(sv_name), FALSE));
	   av_data = (AV*) SvRV(*hv_fetch(p_hash, (char *) "DATA", 4, FALSE));
	   a_index = av_len(av_data);
		 //fprintf(stderr, "Array has: %d\n", a_index);
#else
       /* fprintf(stderr, "getting table parameter: %s \n", table[tab_cnt].name); */
#ifdef DOIBMWKRND
      hv_store(  hash, table[tab_cnt].name, table[tab_cnt].nlen, newRV_noinc( array = newAV() ), 0);
#else
      hv_store(  hash, table[tab_cnt].name, table[tab_cnt].nlen, newRV_noinc( (SV*) ( array = newAV() ) ), 0);
#endif
#endif
	   /*  grab each table row and push onto an array */
	       if (table[tab_cnt].ithandle != NULL){
	         /* fprintf(stderr, "going to check count\n");
	        fprintf(stderr, "the table count is: %d \n", ItFill(table[tab_cnt].ithandle)); */
	         for (irow = 1; irow <=  ItFill(table[tab_cnt].ithandle); irow++){
#ifdef SAPwithUNICODE
	       //av_push( array, u16to8( ItGetLine( mytables[tab_cnt].ithandle, irow ), mytables[tab_cnt].leng ) );
    	       ptr = ItGetLine(table[tab_cnt].ithandle, irow);
	           av_push(array, newRV_noinc((SV*) (av_fields = newAV())));
	           for (j = 0; j <= a_index; j++) {
				    	 av_field = (AV*) SvRV(*av_fetch(av_data, j, FALSE));
    					 itype = SvIV(*av_fetch(av_field, 0, FALSE));
	    				 //fprintf(stderr, "Field: %d type: %d offset: %d len: %d\n", j, itype, SvIV(*av_fetch(av_field, 1, FALSE)), SvIV(*av_fetch(av_field, 2, FALSE)));
    			     if (itype == RFCTYPE_CHAR ||
	    		         itype == RFCTYPE_BYTE ||
		    	         itype == RFCTYPE_NUM ||
			             itype == RFCTYPE_DATE ||
			             itype == RFCTYPE_TIME){
    	           av_push(av_fields, u16to8((char *)ptr+(SvIV(*av_fetch(av_field, 1, FALSE))), SvIV(*av_fetch(av_field, 2, FALSE))));
	    				 } else {
	               av_push(av_fields, newSVpv((char *)ptr+(SvIV(*av_fetch(av_field, 1, FALSE))), SvIV(*av_fetch(av_field, 2, FALSE))));
				    	 };
    	       };
#else
	            av_push( array, newSVpv( ItGetLine( table[tab_cnt].ithandle, irow ), table[tab_cnt].leng ) );
#endif
	         };
	       };
	   
	     Safefree(table[tab_cnt].name);
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
#ifdef SAPwithUNICODE
          RfcRaise( handle, (SAP_UC *) u8to16(sv_type) );
#else
          RfcRaise( handle, SvPV(sv_type, PL_na) );
#endif
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
	   parameter[exp_cnt].leng = SvIV( *hv_fetch( p_hash, (char *) "LEN", 3, FALSE ) );
	   parameter[exp_cnt].type = SvIV( *hv_fetch( p_hash, (char *) "INTYPE", 6, FALSE ) );
#ifdef SAPwithUNICODE
	   parameter[exp_cnt].name = (SAP_UC *) u8to16( h_key );
		//fprintfU(stderr, cU("export name: %s#\n"), myexports[exp_cnt].name);
		//fprintf(stderr, "parameter length: %d\n", myexports[exp_cnt].leng);
		//fprintf(stderr, "parameter type: %d\n", myexports[exp_cnt].type);
		 if (hv_exists(p_hash, (char *) "DATA", 4)&& SvTRUE((SV *) *hv_fetch(p_hash, (char *) "DATA", 4, FALSE))) {
	       av_data = (AV*) SvRV(*hv_fetch(p_hash, (char *) "DATA", 4, FALSE));
	       av_fields = (AV*) SvRV(*hv_fetch(p_hash, (char *) "VALUE", 5, FALSE));
	       a_index = av_len(av_data);
		     //fprintf(stderr, "Array has: %d\n", a_index);
	       parameter[exp_cnt].addr = make_space2(parameter[exp_cnt].leng);
	       for (j = 0; j <= a_index; j++) {
					 av_field = (AV*) SvRV(*av_fetch(av_data, j, FALSE));
			     itype = SvIV(*av_fetch(av_field, 0, FALSE));
			     //fprintf(stderr, "Field: %d type: %d offset: %d len: %d\n", j, itype, SvIV(*av_fetch(av_field, 1, FALSE)), SvIV(*av_fetch(av_field, 2, FALSE)));
	         sv_value = (SV*)*av_fetch(av_fields, j, FALSE);
			     if (itype == RFCTYPE_CHAR ||
			         itype == RFCTYPE_BYTE ||
			         itype == RFCTYPE_NUM ||
			         itype == RFCTYPE_DATE ||
			         itype == RFCTYPE_TIME){
	           memcpy((char *)parameter[exp_cnt].addr+(SvIV(*av_fetch(av_field, 1, FALSE))), (ptr = u8to16p(sv_value)), SvCUR(sv_value)*2);
						 free(ptr);
				   } else {
	           memcpy((char *)parameter[exp_cnt].addr+(SvIV(*av_fetch(av_field, 1, FALSE))), SvPV(sv_value, SvCUR(sv_value)), SvCUR(sv_value));
					 };
				 };
			 } else {
			   if (parameter[exp_cnt].type == RFCTYPE_CHAR ||
			       parameter[exp_cnt].type == RFCTYPE_BYTE ||
			       parameter[exp_cnt].type == RFCTYPE_NUM ||
			       parameter[exp_cnt].type == RFCTYPE_DATE ||
			       parameter[exp_cnt].type == RFCTYPE_TIME){
	         //fprintf(stderr, "value: %s\n", *hv_fetch(p_hash, (char *) "VALUE", 5, FALSE));
	         parameter[exp_cnt].leng = SvIV( *hv_fetch( p_hash, (char *) "LEN", 3, FALSE ) ) * 2;
	         parameter[exp_cnt].addr = u8to16l( *hv_fetch(p_hash, (char *) "VALUE", 5, FALSE), &fsize);
	         parameter[exp_cnt].leng = fsize;
		 //fprintf(stderr, "parameter length NOW: %d\n", myexports[exp_cnt].leng);
	         //fprintfU(stderr, cU("value: %s#\n"), myexports[exp_cnt].addr);
                 //for (k=0;k<myexports[exp_cnt].leng;k++){
	         //fprintf(stderr, "%x|", *((char *) myexports[exp_cnt].addr+k));
                 //}
	         //fprintf(stderr, "\n");
            
			   } else {
	         parameter[exp_cnt].addr = make_copy( *hv_fetch(p_hash, (char *) "VALUE", 5, FALSE),
				  	        *hv_fetch(p_hash, (char *) "LEN", 3, FALSE) );
			   }
			 }
#else
	   parameter[exp_cnt].name = make_strdup( h_key );
	   if ( parameter[exp_cnt].name == NULL )
	       return 0;
	   parameter[exp_cnt].addr = make_copy( *hv_fetch(p_hash, (char *) "VALUE", 5, FALSE),
					        *hv_fetch(p_hash, (char *) "LEN", 3, FALSE) );
#endif
	   parameter[exp_cnt].nlen = strlen( SvPV(h_key, PL_na));
	   ++exp_cnt;

	   break;

	   case RFCTABLE:
	     /* construct a table parameter and copy the table rows on to the table handle */
           /* fprintf(stderr, "adding table parameter name is: %s\n", SvPV(h_key, PL_na)); */
#ifdef SAPwithUNICODE
	     table[tab_cnt].name = (SAP_UC *) u8to16( h_key );
	     av_data = (AV*) SvRV(*hv_fetch(p_hash, (char *) "DATA", 4, FALSE));
	     av_fields = (AV*) SvRV(*hv_fetch(p_hash, (char *) "VALUE", 5, FALSE));
	     data_index = av_len(av_data);
		   //fprintf(stderr, "Array has: %d\n", data_index);
#else
	   table[tab_cnt].name = make_strdup( h_key );
	   if ( table[tab_cnt].name == NULL )
	       return 0;
#endif
	   table[tab_cnt].nlen = strlen( SvPV(h_key, PL_na));
	   table[tab_cnt].leng = SvIV( *hv_fetch( p_hash, (char *) "LEN", 3, FALSE ) );
     table[tab_cnt].itmode = RFC_ITMODE_BYREFERENCE;
     //table[tab_cnt].type = RFCTYPE_CHAR; 
	   /* maybe should be RFCTYPE_BYTE */
     table[tab_cnt].type = SvIV( *hv_fetch( p_hash, (char *) "INTYPE", 6, FALSE ) );
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
#ifdef SAPwithUNICODE
	       av_fields = (AV*) SvRV(*av_fetch( array, j, FALSE ));
				 //fprintf(stderr, "av_fields: %d\n", av_len(av_fields));
		     rowptr = ItAppLine(table[tab_cnt].ithandle);
	       for (k = 0; k <= data_index; k++) {
					 av_field = (AV*) SvRV(*av_fetch(av_data, k, FALSE));
			     itype = SvIV(*av_fetch(av_field, 0, FALSE));
			     /* fprintf(stderr, "Field: %d type: %d offset: %d len: %d\n", k, itype, SvIV(*av_fetch(av_field, 1, FALSE)), SvIV(*av_fetch(av_field, 2, FALSE))); */
	         sv_value = (SV*)*av_fetch(av_fields, k, FALSE);
			     if (itype == RFCTYPE_CHAR ||
			         itype == RFCTYPE_BYTE ||
			         itype == RFCTYPE_NUM ||
			         itype == RFCTYPE_DATE ||
			         itype == RFCTYPE_TIME){
	           memcpy((char *)rowptr+((int)SvIV(*av_fetch(av_field, 1, FALSE))), (ptr = u8to16p(sv_value)), SvCUR(sv_value)*2);
						 free(ptr);
				   } else {
	           memcpy((char *)rowptr+((int)SvIV(*av_fetch(av_field, 1, FALSE))), SvPV(sv_value, SvCUR(sv_value)), SvCUR(sv_value));
					 };
				 };
#else
	       Copy(  SvPV( *av_fetch( array, j, FALSE ), PL_na ),
		      ItAppLine( table[tab_cnt].ithandle ),
		      table[tab_cnt].leng,
		      char );
#endif
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
#ifdef SAPwithUNICODE
    if (strlenU(current_tid) > 0)
       XPUSHs(u16to8((char *)current_tid, strlenU(current_tid)*2));
#else
    if (strlen(current_tid) > 0)
       XPUSHs(newSVpvf("%s", current_tid));
#endif

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
    AV*           array;
    int           a_index;
    SAP_UC *p;
#ifdef SAPwithUNICODE
		char * ptr;
#endif
    int i;

    parameter[0].name = NULL;
    parameter[0].nlen = 0;
    parameter[0].leng = 0;
    parameter[0].addr = NULL;
    parameter[0].type = 0;

    table[0].name =  cU("DOCU");
#ifdef SAPwithUNICODE
	  table[0].nlen = strlenU(table[0].name);
	  table[0].leng = 160;
#else
	  table[0].nlen = strlen(table[0].name);
	  table[0].leng = 80;
#endif
    table[0].type = RFCTYPE_CHAR;
    table[0].itmode = RFC_ITMODE_BYREFERENCE;

    table[1].name = NULL;
    table[1].ithandle = NULL;
    table[1].nlen = 0;
    table[1].leng = 0;
    table[1].type = 0;

    rc = RfcGetData( handle, parameter, table );
    if( rc != RFC_OK ) return rc;

    /* get the documentation out of the array */
    array = (AV*) SvRV( sv_store_docu );
    a_index = av_len( array );
    for (i = 0; i <= a_index; i++) {
       /*Copy(  SvPV( *av_fetch( array, i, FALSE ), PL_na ),
	      ItAppLine( table[0].ithandle ), table[0].leng, char ); */
       p = (SAP_UC *) ItAppLine( table[0].ithandle );
#ifdef SAPwithUNICODE
			 sprintfU(p, cU("%s"), (char *)(ptr = u8to16(*av_fetch( array, i, FALSE ))));
			 free(ptr);
#else
			 sprintf(p, "%s", SvPV( *av_fetch( array, i, FALSE ), PL_na ));
#endif

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
#define NL cU("\n")

static SAP_UC * do_docu_docu( void )
{
   static SAP_UC docu[] =
 cU("This is the override function for the standard self         ")      NL
 cU("discovery documentation function.              ")                   NL
 cU("")                                                                  NL
 cU("IMPORTING")                                                         NL
 cU("TABLES")                                                            NL
 cU("  DOCU           C(80)")                                            NL
 cU("    internal table contains the documentaiton data.          ")     NL
   ;

   return docu;
}










MODULE = SAP::Rfc	PACKAGE = SAP::Rfc	

PROTOTYPES: DISABLE


SV *
MyInit ()

SV *
MyBcdToChar (sv_bcd)
	SV *	sv_bcd

SV *
MyIsUnicode ()

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
MyGetStructure (sv_handle, sv_structure)
	SV *	sv_handle
	SV *	sv_structure

SV *
MyInstallStructure (sv_handle, sv_structure)
	SV *	sv_handle
	SV *	sv_structure

SV *
MyRfcPing (sv_handle)
	SV *	sv_handle

SV *
MySysinfo (sv_handle)
	SV *	sv_handle

SV *
MyGetInterface (sv_handle, sv_function)
	SV *	sv_handle
	SV *	sv_function

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

SV *
my_register (sv_conn, sv_docu, sv_ifaces, sv_saprfc)
	SV *	sv_conn
	SV *	sv_docu
	SV *	sv_ifaces
	SV *	sv_saprfc

SV *
my_one_loop (sv_handle, sv_wait)
	SV *	sv_handle
	SV *	sv_wait

