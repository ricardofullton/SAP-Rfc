package SAP::Rfc;

use strict;

require DynaLoader;
require Exporter;
use vars qw(@ISA $VERSION @EXPORT_OK);
$VERSION = '1.12';
@ISA = qw(DynaLoader Exporter);

sub dl_load_flags { 0x01 }
SAP::Rfc->bootstrap($VERSION);

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
use constant RFCTYPE_INT1  => 10;


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

# unless we are creating a registered RFC
# eg. SAP => external program
    unless (exists $self->{'TPNAME'}){
# create the connection string and login to SAP
      #warn "THE LOGIN STRING: ".login_string( $self )."\n";
      my $conn = MyConnect( login_string( $self ) );

      die "Unable to connect to SAP" unless $conn =~ /^\d+$/;
      $self->{HANDLE} = $conn;
    }

# create the object and return it
    bless ($self, $class);
    return $self;
}


sub convtype {
  my $datatype = shift;

  if ($datatype eq RFCTYPE_CHAR){
    # Character
    return "C";
  } elsif ($datatype eq RFCTYPE_BYTE){
    # Integer
    return "X";
  } elsif ($datatype eq RFCTYPE_INT){
    # Hex
    return "I";
  } elsif ($datatype eq RFCTYPE_INT1){
    # Very Short Integer
    return "b";
  } elsif ($datatype eq RFCTYPE_INT2){
    # Short Integer
    return "s";
  } elsif ($datatype eq RFCTYPE_DATE){
    # Date
    return "D";
  } elsif ($datatype eq RFCTYPE_TIME){
    # Time
    return "T";
  } elsif ($datatype eq RFCTYPE_BCD){
    # Binary Coded Decimal eg. CURR QUAN etc
    return "P";
  } elsif ($datatype eq RFCTYPE_NUM){
    #  Numchar
    return "N";
  } elsif ($datatype eq RFCTYPE_FLOAT){
    #  Float
    return "F";
  } else {
    # Character
    return "C";
  };

}

sub accept {

  my $self = shift;
  die "must have TPNAME, GWHOST and GWSERV to Register RFCs\n"
    unless exists $self->{'GWHOST'} &&
           exists $self->{'GWSERV'} &&
           exists $self->{'TPNAME'};

  my $conn = "-a ".$self->{'TPNAME'}." -g ".$self->{'GWHOST'}.
             " -x ".$self->{'GWSERV'};
  $conn .= " -t " if $self->{'TRACE'} > 0;

  my $d = "";
  foreach my $iface (sort keys %{$self->{'INTERFACES'}}){
    my $if = $self->{'INTERFACES'}->{$iface};
    $d .= "Function Name: $iface\nIMPORTING\n";
    map { if ($_->type() eq RFCIMPORT){ $d .= "     ".sprintf("%-30s",$_->name())."     ".convtype($_->intype())."(".$_->leng().")\n" }
	  } ( $if->parms() );
    $d .= "EXPORTING\n";
    map { if ($_->type() eq RFCEXPORT){ $d .= "     ".sprintf("%-30s",$_->name())."     ".convtype($_->intype())."(".$_->leng().")\n" }
	  } ( $if->parms() );
    $d .= "TABLES\n";
    map { my $tab = $_;
	  $d .= "     ".sprintf("%-30s",$tab->name())."     C(".$_->leng().")\n";
	} ( $if->tabs() );
    $d .= " \n";
  }

  #warn "docu: $d\n";
  my $docu = [ map { pack("A80",$_) } split(/\n/,$d) ];

  my $ifaces = { map { $_->name() => $_->iface(1) } values %{$self->{'INTERFACES'}} };

  return my_accept($conn, $docu, $ifaces);

}

sub Handler {

  my $handler = shift;
  my $iface = shift;
  my $data = shift;

  #use Data::Dumper;
  #warn "handler is: ".Dumper($handler);
  #warn "iface is: ".Dumper($iface);
  #warn "data is: ".Dumper($data);

  map {
	  $_->intvalue( intoext( $_, $data->{$_->name()} ) )
	  } ( $iface->parms() );
      $iface->emptyTables();
  map { my $tab = $_;
	    map { $tab->addRow( $_ ) }
	        ( @{$data->{$tab->name()}} )
	} ( $iface->tabs() );
 
  my $result = "";
  eval { $result = &$handler( $iface ); };
  if ($@ || ! $result){
        #warn "execution of handler failed: $@\n";
	$result = { '__EXCEPTION__' => "$@" || "handler exec failed" };
  } else {
        $result = $iface->iface;
  }
  #warn "Result is going to be: ".Dumper($result);
  return $result;

}


# return a formated connection string for login
sub login_string {

  my $self = shift;
  my $connect = undef;
  $self->{USER} = uc( $self->{USER} );
  $self->{PASSWD} = uc( $self->{PASSWD} );

# create the login string but only return valid parameters
  #map { $connect.= $_ . "=\"" . $self->{$_} . "\" " } keys %{$self};
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
  if (ref($iface) eq 'SAP::Iface'){
    $self->{'INTERFACES'}->{$iface->name()} = $iface;
  }
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
  
  if ($ifc->{'__RETURN_CODE__'} ne '0') {
  	$self->{ERROR} = $ifc->{'__RETURN_CODE__'};
	return undef;
  }

  my $interface = new SAP::Iface(NAME => $iface);
#  print STDERR "VESION: ".Dumper($info)."\n";
  for my $row ( @{ $ifc->{'PARAMS_P'} } ){
#      print STDERR "PARAM ROW: $row \n";
      my ($type, $name, $tabname, $field, $datatype,
          $pos, $off, $intlen, $decs, $default, $text ) =
# record structure changes from release 3.x to 4.x 
	      unpack( ( $info->{RFCSAPRL} =~ /^[4-9]\d\w\s$/ ) ?
		      "A A30 A30 A30 A A4 A6 A6 A6 A21 A79 A1" :
		      "A A30 A10 A10 A A4 A6 A6 A6 A21 A79", $row );
#      print STDERR "DATA TYPE: #$datatype# \n";
#      print STDERR "FIELD: #$field# \n";
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
#      } elsif ( ($datatype eq " " or ! $datatype ) and $type ne "X"){
      } elsif ( 
      # new style
         ( $datatype eq "u" or $datatype eq "h" or $datatype eq " " or ! $datatype ) and $field eq "" and $type ne "X"
#         ( $info->{'RFCSAPRL'} =~ /^6/ and ( $datatype eq "u" or $datatype eq "h" ) and $field eq "" and $type ne "X")
#      # old style
#      or ( $info->{'RFCSAPRL'} !~ /^6/ and ($datatype eq " " or ! $datatype ) and $type ne "X")
              ){
	  # do a structure object
#	  print STDERR " $name creating a structure: name - $tabname - field - $field - $datatype - $type\n";
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
			       RFCINTTYP => $info->{'RFCINTTYP'},
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
			       RFCINTTYP => $info->{'RFCINTTYP'},
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
  # stash a copy of sysinfo on the iface
  $interface->{'SYSINFO'} = $info;
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
  
  if ($str->{'__RETURN_CODE__'} ne '0') {
  	$self->{ERROR} = $str->{'__RETURN_CODE__'};
	return undef;
  }
  
  $struct = SAP::Struc->new( NAME => $struct, RFCINTTYP => $info->{'RFCINTTYP'} );
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
  
  if ($ping->{'__RETURN_CODE__'} eq '0') {
  	return 1;
  } else {
  	$self->{ERROR} = $ping->{'__RETURN_CODE__'};
	return undef;
  }
  
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
  
    if ($sysinfo->{'__RETURN_CODE__'} ne '0') {
	$self->{ERROR} = $sysinfo->{'__RETURN_CODE__'};
	return undef;
    }

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

#  print STDERR "IFACE: ".Dumper($iface->iface );

  my $result = MyRfcCallReceive( $self->{HANDLE}, $iface->name, $iface->iface );

  if ($DEBUG){
      use  Data::Dumper;
      print "RFC CALL: ", $iface->name(), " RETURN IS: ".Dumper( $result )." \n";
  };
  
  if ( $result->{'__RETURN_CODE__'} ne "0" ){
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
    my $value = shift || "";

    if ( $parm->intype() == RFCTYPE_INT ){
	return unpack("N", $value);
    } elsif ( $parm->intype() == RFCTYPE_FLOAT ){
	return unpack("d",$value);
    } elsif ( $parm->intype() == RFCTYPE_BCD ){
	#  All types of BCD
	$value = "0" unless $value;
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


# Return error message
sub error{

  my $self = shift;
  my $msg = $self->{ERROR};
  $msg =~ s/^.+MESSAGE\s*//;
  return $msg;
  
}



=head1 NAME

SAP::Rfc - Perl extension for performing RFC Function calls against an SAP R/3
System.  Please refer to the README file found with this distribution.
This Distribution also allows the creation of registered RFCs so that an SAP
system can call arbitrary Perl code created in assigned callbacks

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

or pass a list of hash refs like so:
$it->OPTIONS( [ { TEXT => "NAME LIKE 'RS%'" } ] );

$rfc->callrfc( $it );

print "NO. PROGS: ".$it->tab('DATA')->rowCount()." \n";
print join("\n",( $it->DATA ));

$rfc->close();



=head1 DESCRIPTION

  The best way to describe this package is to give a brief over view, and
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


error
  $rfc->error();
  Returns error string if previous call returned undef (currenty supported for discover, structure, is_connected and sapinfo).

accept()
This is the main function to initiate a registered RFC. Consider this example that implements the
same functionality as the standard rfcexec executable that comes with all SAP R/3 server 
implementations:

  use SAP::Rfc;
  use SAP::Iface;
  use Data::Dumper;

  # construct the Registered RFC conection
  my $rfc = new SAP::Rfc(
                TPNAME   => 'wibble.rfcexec',
                GWHOST   => '172.22.50.1',
                GWSERV   => '3300',
                TRACE    => '1' );

  # Build up the interface definition that the ABAP code is going to
  # call including the subroutine reference that will be invoked
  # on handling incoming requests
  my $iface = new SAP::Iface(NAME => "RFC_REMOTE_PIPE", HANDLER => \&do_remote_pipe);

  $iface->addParm( TYPE => $iface->RFCIMPORT,
                   INTYPE => $iface->RFCTYPE_CHAR,
                   NAME => "COMMAND",
                   LEN => 256);

  $iface->addParm( TYPE => $iface->RFCIMPORT,
                   INTYPE => $iface->RFCTYPE_CHAR,
                   NAME => "READ",
                   LEN => 1);

  $iface->addTab( NAME => "PIPEDATA",
                  LEN => 80);

  # add the interface definition to the available list of RFCs
  $rfc->iface($iface);

  # kick off the main event loop - register the RFC connection
  # and wait for incoming calls
  $rfc->accept();

  ...

  # the callback subroutine
  # the subroutine receives one argument of an SAP::Iface
  # object that has been populated with the inbound data
  # the callback must return "TRUE" or this is considered
  # an EXCEPTION
  sub do_remote_pipe {
    my $iface = shift;
    warn "Running do_remote_pipe...\n";
    my $ls = $iface->COMMAND;
    $iface->PIPEDATA( [ map { pack("A80",$_) } split(/\n/, `$ls`) ]);
    warn "   Data: ".Dumper($iface->PIPEDATA);
    return 1;
  }


=head1 AUTHOR

Piers Harding, piers@ompa.net.

But Credit must go to all those that have helped.


=head1 SEE ALSO

perl(1), SAP::Iface(3).

=cut


1;
