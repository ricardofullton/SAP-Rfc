package SAP::Rfc;

use strict;

use vars qw($VERSION);
$VERSION = '0.97';

use SAP::Iface;

use constant RFCIMPORT     => 0;
use constant RFCEXPORT     => 1;
use constant RFCTABLE      => 2;

use constant RFCTYPE_CHAR  => 0;
use constant RFCTYPE_DATE  => 1;
use constant RFCTYPE_BCD   => 2;
use constant RFCTYPE_TIME  => 3;
use constant RFCTYPE_BYTE  => 4;
use constant RFCTYPE_NUM   => 6;
use constant RFCTYPE_FLOAT => 7;
use constant RFCTYPE_INT   => 8;
use constant RFCTYPE_INT2  => 9;

## Ensure that the temp directory exists before Inline is invoked
#BEGIN { `mkdir -p /tmp/_Inline/saprfc` if ! -d '/tmp/_Inline/saprfc'; };

# Config for C compiler - the directories may need 
#   altering - these directories follow the typical 
#   installation path of the SAP RFCSDK under Linux
use Inline ( C=> Config =>
#                DIRECTORY => '/tmp/_Inline/saprfc',
                INC => '-I/usr/sap/rfcsdk/include',
#                LIBS => '-lm -ldl -lpthread -L/usr/sap/rfcsdk/lib -lrfc' );
                LIBS => '-lm -ldl -lpthread -L/usr/sap/rfcsdk/lib -lrfccm' );
#  This change will point to the new SAP threaded RFC library librfccm.so
#    Either should do, but librfccm is probably better on other UNIXs

# Config for Inline::MakeMaker
use Inline C=> 'DATA',
                NAME => 'SAP::Rfc',
                VERSION => '0.97';


# Globals
my $loginfile = './testconn';

# sysinfo structure size
my @SYSINFO = (
    { NAME => 'RFCPROTO',   LEN  => 3 },
    { NAME => 'RFCCHARTYP', LEN  => 4 },
    { NAME => 'RFCINTTYP',  LEN  => 3 },
    { NAME => 'RFCFLOTYP',  LEN  => 3 },
    { NAME => 'RFCDEST',    LEN  => 32 },
    { NAME => 'RFCHOST',    LEN  => 8 },
    { NAME => 'RFCSYSID',   LEN  => 8 },
    { NAME => 'RFCDATABS',  LEN  => 8 },
    { NAME => 'RFCDBHOST',  LEN  => 32 },
    { NAME => 'RFCDBSYS',   LEN  => 10 },
    { NAME => 'RFCSAPRL',   LEN  => 4 },
    { NAME => 'RFCMACH',    LEN  => 5 },
    { NAME => 'RFCOPSYS',   LEN  => 10 },
    { NAME => 'RFCTZONE',   LEN  => 6 },
    { NAME => 'RFCDAYST',   LEN  => 1 },
    { NAME => 'RFCIPADDR',  LEN  => 15 },
    { NAME => 'RFCKERNRL',  LEN  => 4 },
    { NAME => 'RFCHOST2',   LEN  => 32 },
    { NAME => 'RFCSI_RESV', LEN  => 12 }
);

 
#  valid login parameters
my $VALID =  {
    SNC_MODE => 1,
    SNC_QOP => 1,
    SNC_MYNAME => 1,
    SNC_PARTNERNAME => 1,
    SNC_LIB => 1,
    CLIENT => 1,
    PASSWD => 1,
    LANG => 1,
    LCHECK => 1,
    USER => 1,
    ASHOST => 1,
    GWHOST => 1,
    GWSERV => 1,
    MSHOST => 1,
    GROUP => 1,
    R3NAME => 1,
    DEST => 1,
    SYSNR => 1,
    TPNAME => 1,
    TPHOST => 1,
    TRACE => 1,
    ABAP_DEBUG => 1,
    USE_SAPGUI => 1,
    TYPE => 1
  };


# Global debug flag
my $DEBUG = undef;



# Tidy up open Connection when DESTROY Destructor Called
sub DESTROY {
    my $self = shift;
    MyDisconnect( $self->{'handle'} )
          if exists $self->{'handle'};
}


# Construct a new SAP::Rfc Object.
sub new {

    my @keys = ();
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my @rest = @_;
    if ( scalar @rest == 1 ){
	$loginfile = $rest[0] if $rest[0];
	if (-f $loginfile){
	    open (FIL,"<$loginfile")
		or die "$! : could not open login file $loginfile";
	    my @file = <FIL>;
	    close FIL;
	    map { push @keys, split "\t",$_ } @file;
	    chomp @keys;
	}
    };
    
    my $self = {
	INTERFACES => {},
	CLIENT => "000",
	USER   => "SAPCPIC",
	PASSWD => "ADMIN",
	LANG   => "EN",
	LCHECK   => "0",
	@keys,
	@rest
	};


# validate the login parameters
    map { delete $self->{$_} unless exists $VALID->{$_} } keys %{$self};

# create the connection string and login to SAP
    my $conn = MyConnect( login_string( $self ) );

    die "Unable to connect to SAP" unless $conn =~ /^\d+$/;
    $self->{HANDLE} = $conn;

# create the object and return it
    bless ($self, $class);
    return $self;
}


# return a formated connection string for login
sub login_string {

  my $self = shift;
  my $connect = undef;
  $self->{USER} = uc( $self->{USER} );
  $self->{PASSWD} = uc( $self->{PASSWD} );

# create the login string but only return valid parameters
  map { $connect.= $_ . "=" . $self->{$_} . " " } keys %{$self};

  return $connect;
}



# method to return the current date in ABAP DATE format
sub sapdate{

  my @date = localtime;
  return pack("A4 A2 A2", ($date[5] + 1900,
      sprintf("%02d",$date[4] + 1), sprintf("%02d",$date[3])));

}


# method to return the current time in ABAP TIME format
sub saptime{

  my @date = localtime;
  return pack("A2 A2 A2", (sprintf("%02d",$date[2]),
                           sprintf("%02d",$date[1]),
			   sprintf("%02d",$date[0])));

}


# method to access aggregate functions SAP::Interface
sub iface{

  my $self = shift;
  die "No Interface supplied to RFC " if ! @_;
  my $iface = shift;
  return $self->{INTERFACES}->{$iface};

}


# method to find the structure of an interface
sub discover{
  my $self = shift;
  die "No Interface supplied to RFC " if ! @_;
  my $iface = shift;
  die "RFC is NOT connected for interface discovery!"
     if ! is_connected( $self );
  my $info = $self->sapinfo();

  my $if = {
      'FUNCNAME' => { 'TYPE' => RFCEXPORT,
		      'VALUE' => $iface,
		      'INTYPE' => RFCTYPE_CHAR,
		      'LEN' => length($iface) }, 
      'PARAMS_P'    => { 'TYPE' => RFCTABLE,
			 'VALUE' => [],
			 'INTYPE' => RFCTYPE_BYTE,
			 'LEN' => 215 } 
  }; 

  my $ifc = MyRfcCallReceive( $self->{HANDLE},
			      "RFC_GET_FUNCTION_INTERFACE_P",
			      $if );
  
  return  undef if $ifc->{'__RETURN_CODE__'} != 0;

  my $interface = new SAP::Iface(NAME => $iface);
  for my $row ( @{ $ifc->{'PARAMS_P'} } ){
      my ($type, $name, $tabname, $field, $datatype,
          $pos, $off, $intlen, $decs, $default, $text ) =
# record structure changes from release 3.x to 4.x 
	      unpack( ( $info->{RFCSAPRL} =~ /^[4-9]\d\w\s$/ ) ?
		      "A A30 A30 A30 A A4 A6 A6 A6 A21 A79 A1" :
		      "A A30 A10 A10 A A4 A6 A6 A6 A21 A79", $row );
      $name =~ s/\s//g;
      $tabname =~ s/\s//g;
      $field =~ s/\s//g;
      $intlen = int($intlen);
      $decs = int($decs);
      # if the character value default is in quotes - remove quotes
      if ($default =~ /^\'(.*?)\'\s*$/){
	  $default = $1;
	  # if the value is an SY- field - we have some of them in sapinfo
      } elsif ($default =~ /^SY\-(\w+)\W*$/) {
	  $default = 'RFC'.$1;
	  if ( exists $info->{$default} ) {
	      $default = $info->{$default};
	  } else {
	      $default = undef;
	  };
      };
      my $structure = "";
      if ($datatype eq "C"){
	  # Character
	  $datatype = RFCTYPE_CHAR;
	  $default = " " if $default =~ /^SPACE\s*$/;
#	  print STDERR "SET $name TO $default \n";
      } elsif ($datatype eq "X"){
	  # Integer
	  $datatype = RFCTYPE_BYTE;
	  $default = pack("H*", $default) if $default;
      } elsif ($datatype eq "I"){
	  # Integer
	  $datatype = RFCTYPE_INT;
	  $default = int($default) if $default;
      } elsif ($datatype eq "s"){
	  # Short Integer
	  $datatype = RFCTYPE_INT2;
	  $default = int($default) if $default;
      } elsif ($datatype eq "D"){
	  # Date
	  $datatype = RFCTYPE_DATE;
	  $default = '00000000';
	  $intlen = 8;
      } elsif ($datatype eq "T"){
	  # Time
	  $datatype = RFCTYPE_TIME;
	  $default = '000000';
	  $intlen = 6;
      } elsif ($datatype eq "P"){
	  # Binary Coded Decimal eg. CURR QUAN etc
	  $datatype = RFCTYPE_BCD;
	  #$default = 0;
      } elsif ($datatype eq "N"){
	  #  Numchar
	  $datatype = RFCTYPE_NUM;
	  #$default = 0;
	  $default = sprintf("%0".$intlen."d", $default) 
	      if $default == 0 || $default =~ /^[0-9]+$/;
      } elsif ($datatype eq "F"){
	  #  Float
	  $datatype = RFCTYPE_FLOAT;
	  #$default = 0;
      } elsif ( ($datatype eq " " or ! $datatype ) and $type ne "X"){
	  # do a structure object
	  $structure = structure( $self, $tabname );
	  $datatype = RFCTYPE_BYTE;
      } else {
	  # Character
	  $datatype = RFCTYPE_CHAR;
	  $default = " " if $default =~ /^SPACE\s*$/;
      };
      $datatype = RFCTYPE_CHAR if ! $datatype;
      if ($type eq "I"){
	  #  Export Parameter - Reverse perspective
	  $interface->addParm( 
			       TYPE => RFCEXPORT,
			       INTYPE => $datatype, 
			       NAME => $name, 
			       STRUCTURE => $structure, 
			       DEFAULT => $default,
			       VALUE => $default,
			       DECIMALS => $decs,
			       LEN => $intlen);
      } elsif ( $type eq "E"){
	  #  Import Parameter - Reverse perspective
	  $interface->addParm( 
			       TYPE => RFCIMPORT,
			       INTYPE => $datatype, 
			       NAME => $name, 
			       STRUCTURE => $structure, 
			       VALUE => undef,
			       DECIMALS => $decs,
			       LEN => $intlen);
      } elsif ( $type eq "T"){
	  #  Table
	  $interface->addTab(
			     # INTYPE => $datatype, 
			     INTYPE => RFCTYPE_BYTE, 
			     NAME => $name,
			     STRUCTURE => $structure, 
			     LEN => $intlen);
      } else {
	  # This is an exception definition
	  $interface->addException( $name );
      };
  };
  return $interface;

}


# method to return a structure object of SAP::Structure type
sub structure{

  my $self = shift;
  my $struct = shift;
  die "RFC is NOT connected for structure discovery!"
     if ! is_connected( $self );
  # do RFC call to obtain structure 
  if ($DEBUG){
    print "RFC CALL for STRUCTURE: $struct \n";
  };
  my $info = $self->sapinfo();

  my $iface = {
      'TABNAME' => { 'TYPE' => RFCEXPORT,
		     'VALUE' => $struct,
		     'INTYPE' => RFCTYPE_CHAR,
		     'LEN' => length($struct) }, 
      'FIELDS'    => { 'TYPE' => RFCTABLE,
		       'VALUE' => [],
		       'INTYPE' => RFCTYPE_BYTE,
		       'LEN' => 83 } 
  }; 

  my $str = MyRfcCallReceive( $self->{HANDLE},
			      "RFC_GET_STRUCTURE_DEFINITION_P",
			      $iface );
  
  return  undef if $str->{'__RETURN_CODE__'} != 0;
  
  $struct = SAP::Struc->new( NAME => $struct );
  map {
      my ($tabname, $field, $pos, $off, $intlen, $decs, $exid ) =
# record structure changes from 3.x to 4.x
	  unpack( ( $info->{RFCSAPRL} =~ /^[4-9]\d\w\s$/ ) ?
		  "A30 A30 A4 A6 A6 A6 A" : "A10 A10 A4 A6 A6 A6 A", $_ );
      $struct->addField( 
			 NAME     => $field,
			 LEN      => $intlen,
			 OFFSET   => $off,
			 DECIMALS => $decs,
			 INTYPE   => $exid
			 )
      }  ( @{ $str->{'FIELDS'} } );
  return $struct;

}

#  get the handle
sub handle{

  my $self = shift;
  return  $self->{HANDLE};
  
}


#  test the open connection status
sub is_connected{

  my $self = shift;
  my $ping = MyRfcCallReceive( $self->{HANDLE}, "RFC_PING", {} );
  
  return  $ping->{'__RETURN_CODE__'} == 0 ? 1 : undef;
  
}

# Call The RFCSI_EXPORT Function module to
#  get the instance information of the connected system
sub sapinfo {
  my $return = "";
  my $output = "";

  my $self = shift;

  if ( ! exists $self->{SYSINFO} ){
    die "SAP Connection Not Open for SYSINFO "
      if ! is_connected( $self );

  my $sysinfo = MyRfcCallReceive( $self->{HANDLE}, "RFC_SYSTEM_INFO",
				  {   'RFCSI_EXPORT' => {
				      'TYPE' => RFCIMPORT,
				      'VALUE' => '',
				      'INTYPE' => RFCTYPE_CHAR,
				      'LEN' => 200 }
				  }
				  );
  
    return  undef if $sysinfo->{'__RETURN_CODE__'} != 0;

    my $pos = 0;
    my $info = {};
    map {
	$info->{$_->{NAME}} = 
	    substr($sysinfo->{'RFCSI_EXPORT'},$pos, $_->{LEN});
	$pos += $_->{LEN}
    } @SYSINFO;


    $self->{RETURN} = $return;
    $self->{SYSINFO} = $info;
  }

  return  $self->{SYSINFO};

}


# Call The Function module
sub callrfc {
  my $self = shift;
  my $iface = shift;
  my $ref = ref($iface);
  die "this is not an Interface Object!" 
     unless $ref eq "SAP::Iface" and $ref;

  die "SAP Connection Not Open for RFC call "
     if ! is_connected( $self );

  my $result = MyRfcCallReceive( $self->{HANDLE}, $iface->name, $iface->iface);

  if ($DEBUG){
      use  Data::Dumper;
      print "RFC CALL: ", $iface->name(), " RETURN IS: ".Dumper( $result )." \n";
  };
  
  if ( $result->{'__RETURN_CODE__'} != 0 ){
      die "RFC call falied: ".$result->{'__RETURN_CODE__'};
  } else {
      map {
	  $_->intvalue( intoext( $_, $result->{$_->name()} ) )
	  } ( $iface->parms() );
      $iface->emptyTables();
      map { my $tab = $_;
	    map { $tab->addRow( $_ ) }
	        ( @{$result->{$tab->name()}} )
	} ( $iface->tabs() );
  }
}


# convert internal data types to externals
sub intoext{
    my $parm = shift;
    my $value = shift;

    if ( $parm->intype() == RFCTYPE_INT ){
	return unpack("l", $value);
    } elsif ( $parm->intype() == RFCTYPE_FLOAT ){
	return unpack("d",$value);
    } elsif ( $parm->intype() == RFCTYPE_BCD ){
	#  All types of BCD
	my @flds = split(//, unpack("H*",$value));
	if ( $flds[$#flds] eq 'd' ){
	    splice( @flds,0,0,'-');
	} else {
	    splice( @flds,0,0,'+');
	}
	pop( @flds );
	splice(@flds,$#flds - ( $parm->decimals - 1 ),0,'.')
	    if $parm->decimals > 0;
	return join('', @flds);
    } else {
	return $value;
    }

}


# Close the Current Open Handle
sub close {
  my $self = shift;
  if ( exists $self->{HANDLE} ) {
      MyDisconnect( $self->{HANDLE} );
      delete $self->{HANDLE};
      delete $self->{SYSINFO};
      return 1;
  } else {
      return undef;
  };
}





=head1 NAME

SAP::Rfc - Perl extension for performing RFC Function calls against an SAP R/3
System.  Please refer to the README file found with this distribution.

=head1 SYNOPSIS

  use SAP::Rfc;
  $rfc = new SAP::Rfc(
		      ASHOST   => 'myhost',
		      USER     => 'ME',
		      PASSWD   => 'secret',
		      LANG     => 'EN',
		      CLIENT   => '200',
		      SYSNR    => '00',
		      TRACE    => '1' );

my $it = $rfc->discover("RFC_READ_TABLE");

$it->QUERY_TABLE('TRDIR');
$it->ROWCOUNT( 2000 );
$it->OPTIONS( ["NAME LIKE 'RS%'"] );

$rfc->callrfc( $it );

print "NO. PROGS: ".$it->tab('DATA')->rowCount()." \n";
print join("\n",( $it->DATA ));

$rfc->close();



=head1 DESCRIPTION

  The best way to discribe this package is to give a brief over view, and
  then launch into several examples.
  The SAP::Rfc package works in concert with several other packages that
  also come with same distribution, these are SAP::Iface, SAP::Parm,
  SAP::Tab, and SAP::Struc.  These come
  together to give you an object oriented programming interface to
  performing RFC function calls to SAP from a UNIX based platform with
  your favourite programming language - Perl.
  A SAP::Rfc object holds together one ( and only one ) connection to an
  SAP system at a time.  The SAP::Rfc object can hold one or many SAP::Iface
  objects, each of which equate to the definition of an RFC Function in
  SAP ( trans SE37 ). Each SAP::Iface object holds one or many
  SAP::Parm, and/or SAP::Tab objects, corresponding to
  the RFC Interface definition in SAP ( SE37 ).
  For all SAP::Tab objects, and for complex SAP::Parm objects,
   a SAP::Struc object can be defined.  This equates to a
  structure definition in the data dictionary ( SE11 ).
  Because the manual definition of interfaces and structures is a boring
  and tiresome exercise, there are specific methods provided to 
  automatically discover, and add the appropriate interface definitions
  for an RFC Function module to the SAP::Rfc object ( see methods
  discover, and structure of SAP::Rfc ).


=head1 METHODS:

$rfc->PARM_NAME( 'a value ')
  The parameter or tables can be accessed through autoloaded method calls - this can be useful for setting or getting the parameter values.


discover
  $iface = $rfc->discover('RFC_READ_REPORT');
  Discover an RFC interface definition, and automaticlly add it to an SAP::Rfc object.  This will also define all associated SAP::Parm, SAP::Tab, and SAP::Struc objects.


structure
  $str = $rfc->structure('QTAB');
  Discover and return the definition of a valid data dictionary structure.  This could be subsequently used with an SAP::Parm, or SAP::Tab object.



is_connected
  if ($rfc->is_connected()) {
  } else {
  };
  Test that the SAP::Rfc object is connected to the SAP system.


sapinfo
  %info = $rfc->sapinfo();
  map { print "key: $_ = ", $info{$_}, "\n" }
        sort keys %info;
  Return a hash of the values supplied by the RFC_SYSTEM_INFO function module.  This function is only properly called once, and the data is cached until the RFC connection is closed - then it will be reset next call.
  


callrfc
  $rfc->callrfc('RFC_READ_TABLE');
  Do the actual RFC call - this installs all the Export, Import, and Table Parameters in the actual C library of the XS extension, does the RFC call, Retrieves the table contents, and import parameter contents, and then cleans the libraries storage space again.


close
  $rfc->close();
  Close the current open RFC connection to an SAP system, and then reset cached sapinfo data.



=head1 AUTHOR

Piers Harding, piers@ompa.net.

But Credit must go to all those that have helped.


=head1 SEE ALSO

perl(1), SAP::Iface(3).

=cut



1;

__DATA__

__C__


#include <saprfc.h>
#include <sapitab.h>

#define MAX_PARA 64

#define RFCIMPORT     0
#define RFCEXPORT     1
#define RFCTABLE      2



/* standard error call back handler - installed into connnection object */
static void  DLL_CALL_BACK_FUNCTION  rfc_error( char * operation ){

  RFC_ERROR_INFO_EX  error_info;
  
  fprintf( stderr, "RFC Call/Exception: %s\n", operation );
  RfcLastErrorEx(&error_info);
  fprintf( stderr, "\nGroup       Error group %d", error_info.group );
  fprintf( stderr, "\nKey         %s", error_info.key );
  fprintf( stderr, "\nMessage     %s\n", error_info.message );
  exit(0);

}



/* build a connection to an SAP system */
SV*  MyConnect(char* connectstring){

    RFC_ENV            new_env;
    RFC_HANDLE         handle;
    RFC_ERROR_INFO_EX  error_info;
    
    new_env.allocate = NULL;
    new_env.errorhandler = rfc_error;
    RfcEnvironment( &new_env );
    
    // fprintf(stderr, "CONNECT: %s\n", connectstring);
    handle = RfcOpenEx(connectstring,
		       &error_info);

    if (handle == RFC_HANDLE_NULL){
	RfcLastErrorEx(&error_info);
	fprintf(stderr, "GROUP \t %d \t KEY \t %s \t MESSAGE \t %s \0",
		error_info.group, error_info.key, error_info.message );
	exit(0);
    };
 
    return newSViv( ( int ) handle );
    
}



/* Disconnect from an SAP system */
int  MyDisconnect(SV* sv_handle){

    RFC_HANDLE         handle = SvIV( sv_handle );
    
    RfcClose( handle ); 
    return 1;

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

