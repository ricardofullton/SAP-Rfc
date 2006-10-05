package SAP::Rfc;

=pod

    Copyright (c) 2002 - 2006 Piers Harding.
		    All rights reserved.

=cut

use strict;

require 5.005;

require DynaLoader;
require Exporter;
use Data::Dumper;

#use utf8;

use vars qw(@ISA $VERSION @EXPORT_OK $USECACHE $DEFAULT_CACHE $CACHE);
$VERSION = '1.53';
@ISA = qw(DynaLoader Exporter);

# Only return the exception key for registered RFCs
my $EXCEPTION_ONLY = 0;

# The RFC structure cache
$USECACHE = "";
$DEFAULT_CACHE = ".rfc_cache/";
$CACHE = "";


sub dl_load_flags { $^O =~ /hpux|aix/ ? 0x00 : 0x01 }
SAP::Rfc->bootstrap($VERSION);

use SAP::Iface;
use SAP::Idoc;

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
    TRFC => 1,
    TRFC_CONFIRM => 1,
    TRFC_COMMIT => 1,
    TRFC_ROLLBACK => 1,
    TRFC_CHECK => 1,
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
    TYPE => 1,
    LINTTYP => 1,
    GETSSO2 => 1,
    MYSAPSSO2 => 1,
    X509CERT => 1,
    UNICODE => 1,
  };


# Global debug flag
my $DEBUG = undef;


# Tidy up open Connection when DESTROY Destructor Called
sub DESTROY {
    my $self = shift;
    MyDisconnect( $self->{'HANDLE'} )
          if exists $self->{'HANDLE'};
}


# The default callback for tRFC CHECK event
sub TID_CHECK {
  my $tid = shift;
  warn "in the default TID_CHECK: $tid - see the SAP::Rfc documentation to overide\n";
  return 0;
}


# The default callback for tRFC COMMIT event
sub TID_COMMIT {
  my $tid = shift;
  warn "in the default TID_COMMIT: $tid - see the SAP::Rfc documentation to overide\n";
  return;
}


# The default callback for tRFC ROLLBACK event
sub TID_ROLLBACK {
  my $tid = shift;
  warn "in the default TID_ROLLBACK: $tid - see the SAP::Rfc documentation to overide\n";
  return;
}


# The default callback for tRFC CONFIRM event
sub TID_CONFIRM {
  my $tid = shift;
  warn "in the default TID_CONFIRM: $tid - see the SAP::Rfc documentation to overide\n";
  return;
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
	    open (FIL,"<$loginfile") or die "$! : could not open login file $loginfile";
	    my @file = <FIL>;
	    close FIL;
	    map { push @keys, split "\t",$_ } @file;
	    chomp @keys;
	}
    };
    
    my $self = {
	INTERFACES => {},
        LINTTYP => ( ( join(" ", map { sprintf "%#02x", $_ } unpack("C*",pack("L",0x12345678))) eq "0x78 0x56 0x34 0x12") ? "LIT" : "BIG" ),
	CLIENT => "000",
	#USER   => "SAPCPIC",
	#PASSWD => "ADMIN",
	LANG   => "EN",
	UNICODE => MyIsUnicode(),
	LCHECK   => "0",
	TRFC   => 0,
	TRFC_CHECK => \&SAP::Rfc::TID_CHECK,
	TRFC_COMMIT => \&SAP::Rfc::TID_COMMIT,
	TRFC_ROLLBACK => \&SAP::Rfc::TID_ROLLBACK,
	TRFC_CONFIRM => \&SAP::Rfc::TID_CONFIRM,
	@keys,
	@rest
	};

#	print STDERR "Is unicode: ", MyIsUnicode(), "\n";
#	exit;

# validate the login parameters
  # map { delete $self->{$_} unless exists $VALID->{$_} } keys %{$self};

  # print STDERR "UNICODE: $self->{UNICODE} \n";

  # initialise
 	MyInit();

#	if ($self->{UNICODE}){
#	  require Text::Iconv;
#		Text::Iconv->raise_error(1);
#		$self->{TOUTF8} = new Text::Iconv("UTF-16", "UTF-8");
#		#$self->{TOUTF16} = new Text::Iconv("UTF-8", "UTF-16LE");
#		$self->{TOUTF16} = new Text::Iconv("UTF-8", "UTF-16");
#	}

# unless we are creating a registered RFC
# eg. SAP => external program
  unless (exists $self->{'TPNAME'}){
# create the connection string and login to SAP
    my $conn = MyConnect(login_string($self));
#    my $conn =  $self->{UNICODE} ? 
#			     MyConnect(do_8to16(login_string($self))) :
#					 MyConnect(login_string($self));
    die "Unable to connect to SAP" unless $conn =~ /^\d+$/;
    $self->{'HANDLE'} = $conn;
  }

# ensure that the structure cache has been setup
# if being used
  if ($USECACHE){
    $CACHE = $DEFAULT_CACHE unless $CACHE;
  }

  if ($CACHE){
	  for my $cache_dir ($CACHE,"$CACHE/structs","$CACHE/ifaces","$CACHE/idocs"){
	    mkdir $cache_dir, 0777 unless -d $cache_dir;
	  }
  }

#	print STDERR "Is unicode: ", $self->{UNICODE}, "\n";
#	exit;

# create the object and return it
  bless ($self, $class);
  return $self;
}


sub unicode {
  my $self = shift;
	return $self->{UNICODE};
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
  my $callback = shift || "";
  my $wait = shift || 0;

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

  my $docu = [ (map { chomp($_); pack("A80",$_) } split(/\n/,$d)) ];

  my $ifaces = { map { $_->name() => $_->iface(1) } values %{$self->{'INTERFACES'}} };

  # set the callback up
  $self->{'WAIT'} = $wait || 0;
  $self->{'CALLBACK'} = $callback || undef;
  return my_accept($conn, $docu, $ifaces, $self);
}


sub register {

  my $self = shift;
  my $wait = shift || 0;
  my $callback = shift || "";

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

  my $docu = [ (map { chomp($_); pack("A80",$_) } split(/\n/,$d)) ];

  my $ifaces = { map { $_->name() => $_->iface(1) } values %{$self->{'INTERFACES'}} };

  # set the callback up
  $self->{'WAIT'} = $wait || 0;
  $self->{'CALLBACK'} = $callback || undef;
  return my_register($conn, $docu, $ifaces, $self);
}


sub process {

  my $self = shift;
  my $handle = shift;
	my $wait = shift || 0;
  return my_one_loop($handle, $wait);

}


sub Handler {

  my $handler = shift;
  my $iface = shift;
  my $data = shift;
  my $tid = @_ ? shift @_ : "";

  map {
	  $_->intvalue( intoext( $_, $data->{$_->name()} ) )
	  } ( $iface->parms() );
    $iface->emptyTables();
  map { my $tab = $_;
	    map { $tab->addRow( $_ ) }
	        ( @{$data->{$tab->name()}} )
	} ( $iface->tabs() );
 
  my $result = "";
  eval { $result = &$handler( $iface, $tid ); };
  if ($@ || ! $result){
  	my ($err) =  ($SAP::Rfc::EXCEPTION_ONLY ? ( $@ =~ /^(\w+)\s/) : $@);

	  $result = { '__EXCEPTION__' => "$err" || "handler exec failed" };
  } else {
        $result = $iface->iface;
  }
  return $result;

}


# return a formated connection string for login
sub login_string {

  my $self = shift;
  my $connect = undef;
  #$self->{USER} = uc( $self->{USER} );
  #$self->{PASSWD} = uc( $self->{PASSWD} );

# create the login string but only return valid parameters
  map { unless (/LINTTYP|testconn|TESTCONN|INTERFACE|UTF|HANDLE|TRFC_COMMIT|RETURN|SYSINFO|TRFC_ROLLBACK|TRFC_CONFIRM|TRFC_CHECK/){$connect.= $_ . "=" . $self->{$_} . " "} } keys %{$self};

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


#With that the Method it is possible to launch a program. This feature is
#hevealy used by SAP DMS (Document Management System) which sends and
#receives Files from and to the client.

#Addon from Matthias Flury                                                                       
sub allow_start_program {
   my $self = shift;
   my $program = shift;
   MyAllowStartProgram($program);
   return 1;
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
sub discover {
  my $self = shift;
  die "No Interface supplied to RFC " if ! @_;
  my $iface = shift;
  die "RFC is NOT connected for interface discovery!"
     if ! is_connected( $self );
  my $info = $self->sapinfo();

  if ($CACHE && -f $CACHE."/ifaces/".$iface.".txt"){
    my $iface1;
	  open(IFC, "<$CACHE/ifaces/".$iface.".txt") or 
	  warn "cant open structure file $CACHE/ifaces/".$iface.".txt - $!";
	  $iface = join("",(<IFC>));
	  close IFC;
	  eval($iface);
    $iface1->{'SYSINFO'} = $info;
    #$iface1->{'RFCINTTYP'} = $info->{'RFCINTTYP'};
		foreach my $parm ($iface1->parms(), $iface1->tabs()){
		  next unless $parm->structure;
		  $parm->structure($self->structure($parm->structure->name()));
			$parm->intype($parm->structure->StrType());
		}
	  return $iface1;
  }

#  my $if;
##	if ($self->unicode){
##    $if = {
##          'FUNCNAME' => { 'TYPE' => RFCEXPORT,
##		      #'NAME' => $self->u8to16('FUNCNAME'),
##		      'NAME' => do_8to16('FUNCNAME'),
##		      #'VALUE' => $self->u8to16($iface),
##		      'VALUE' => do_8to16($iface),
##		      'INTYPE' => RFCTYPE_CHAR,
##		      'LEN' => length($iface) * 2 }, 
##          'PARAMS_P'    => { 'TYPE' => RFCTABLE,
##		      #'NAME' => $self->u8to16('PARAMS_P'),
##		      'NAME' => do_8to16('PARAMS_P'),
##			    'VALUE' => [],
##			    'INTYPE' => RFCTYPE_BYTE,
##			    'LEN' => 430 },
##    }; 
##	} else {
#    $if = {
#          'FUNCNAME' => { 'TYPE' => RFCEXPORT,
#		      'VALUE' => pack("A30",$iface),
#		      'INTYPE' => RFCTYPE_CHAR,
#		      #'LEN' => length($iface) }, 
#		      'LEN' => $self->unicode ? 60 : 30 }, 
#          'PARAMS_P'    => { 'TYPE' => RFCTABLE,
#			    'VALUE' => [],
#			    'INTYPE' => RFCTYPE_BYTE,
#			    'LEN' => $self->unicode ? 430 : 215 },
#    }; 
##  }; 

#  my $ifc = MyRfcCallReceive( $self->{'HANDLE'},
##			      #($self->unicode ? $self->u8to16("RFC_GET_FUNCTION_INTERFACE_P") :
##			      ($self->unicode ? do_8to16("RFC_GET_FUNCTION_INTERFACE_P") :
#			      "RFC_GET_FUNCTION_INTERFACE_P",
#			      $if );
#  
#  if ($ifc->{'__RETURN_CODE__'} ne '0') {
#  	$self->{ERROR} = $ifc->{'__RETURN_CODE__'};
#	return undef;
#  }
  my $ifc = MyGetInterface( $self->{'HANDLE'}, $iface);
#  print STDERR "Interface: ".Dumper($ifc)." \n";

  my $interface = new SAP::Iface(NAME => $iface, UNICODE => $self->unicode);
#	print STDERR "building interface ...\n";
  #for my $row ( @{ $ifc->{'PARAMS_P'} } ){
  for my $row ( @{$ifc} ){
#      print STDERR "PARAM ROW: ".Dumper($row)." \n";
#      my ($type, $name, $tabname, $field, $datatype,
#          $pos, $off, $intlen, $decs, $default, $text ) =
# record structure changes from release 3.x to 4.x 
#	      unpack( ( $info->{RFCSAPRL} =~ /^[4-9]\d\w\s$/ ) ?
#		      "A A30 A30 A30 A A4 A6 A6 A6 A21 A79 A1" :
#		      "A A30 A10 A10 A A4 A6 A6 A6 A21 A79", $row );
      my ($type, $name, $tabname, $field, $datatype,
          $pos, $off, $intlen, $decs, $default, $text ) =
					(
					$row->{paramclass},
					$row->{parameter},
					$row->{tabname},
					$row->{fieldname},
					$row->{exid},
					$row->{pos},
					$row->{off1},
					$row->{len1},
					$row->{dec},
					$row->{default},
					$row->{text}
					);
   
      $name =~ s/\s//g;
      $tabname =~ s/\s//g;
      $field =~ s/\s//g;
      $intlen = int($intlen);
#     support UNICODE
      #$intlen = ( $self->{'UNICODE'} ? int($intlen)/2 : int($intlen));
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
	      $default = " " if !$default ||  $default =~ /^SPACE\s*$/;
      } elsif ($datatype eq "X"){
	  # Integer
	      $datatype = RFCTYPE_BYTE;
	      $default = pack("H*", $default) if $default;
      } elsif ($datatype eq "I"){
	  # Integer
	      $datatype = RFCTYPE_INT;
	      $default = int($default) if $default;
      } elsif ($datatype eq "b"){
	  # Single byte Integer
	      $datatype = RFCTYPE_INT1;
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
      } elsif ($datatype eq "N"){
	  #  Numchar
	      $datatype = RFCTYPE_NUM;
	      $default = 0 unless $default;
	      $default = sprintf("%0".$intlen."d", $default) 
	          if $default == 0 || $default =~ /^[0-9]+$/;
      } elsif ($datatype eq "F"){
	  #  Float
	      $datatype = RFCTYPE_FLOAT;
      } elsif ( 
      # new style
         ( $datatype eq "u" or $datatype eq "h" or $datatype eq " " or ! $datatype ) and $field eq "" and $type ne "X"
#         ( $info->{'RFCSAPRL'} =~ /^6/ and ( $datatype eq "u" or $datatype eq "h" ) and $field eq "" and $type ne "X")
#      # old style
#      or ( $info->{'RFCSAPRL'} !~ /^6/ and ($datatype eq " " or ! $datatype ) and $type ne "X")
              ){
	  # do a structure object
	      $structure = structure( $self, $tabname );
	      #$datatype = RFCTYPE_BYTE;
				$datatype = $structure->StrType();
				$intlen = $structure->StrLength();
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
			       TYPE => int(RFCEXPORT),
			       UNICODE => $self->unicode, 
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
			       TYPE => int(RFCIMPORT),
			       UNICODE => $self->unicode, 
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
			       UNICODE => $self->unicode, 
			       RFCINTTYP => $info->{'RFCINTTYP'},
			       #INTYPE => RFCTYPE_BYTE, 
			       INTYPE => $structure->StrType(), 
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
  #$interface->{'RFCINTTYP'} = $info->{'RFCINTTYP'};
	#
#print STDERR "is unicode: ", $self->unicode, "\n";
#exit;

  # save the interface to the cache
  if ($CACHE){
    open(IFC, ">$CACHE/ifaces/".$interface->name().".txt") or
      warn "cant open cache file for $CACHE/".$interface->name().".txt - $!\n";
    $Data::Dumper::Varname = 'iface';
    print IFC Dumper($interface);
    close IFC;
  }
  return $interface;

}


# method to return an IDOC object of SAP::IDOC type
sub lookupIdoc {

  my $self = shift;
  my $idoc = shift;
  if ($CACHE && -f $CACHE."/idocs/".$idoc.".txt"){
    my $idoc1;
  	open(IDOC, "<$CACHE/idocs/".$idoc.".txt") or 
	    warn "cant open structure file $CACHE/idocs/".$idoc.".txt - $!";
	  $idoc = join("",(<IDOC>));
	  close IDOC;
	  eval($idoc);
	  return $idoc1;
  }
  $idoc = new SAP::Idoc( 'NAME' => $idoc, 
                            'SINGLE' => $self->discover('IDOC_INBOUND_SINGLE'),
                            'MANDT' => $self->{'CLIENT'},
							);

  # discover the complete structure of an IDOC
  my $idoctype = $self->discover('IDOCTYPE_READ_COMPLETE');
  $idoctype->PI_IDOCTYP($idoc->name);
  my $segments = $idoctype->tab('PT_SEGMENTS');
  $self->callrfc($idoctype);
  while ( my $row = $segments->nextRow() ){
    $row->{'SEGMENTTYP'} =~ s/\s//g;
	  $idoc->_addSegment($self->structure($row->{'SEGMENTTYP'}), $row);
  }

  # save the structure to the cache
  if ($CACHE){
    open(IDOC, ">$CACHE/idocs/".$idoc->name().".txt") or
      warn "cant open cache file for $CACHE/idocs/".$idoc->name().".txt - $!\n";
    $Data::Dumper::Varname = 'idoc';
    print IDOC Dumper($idoc);
    close IDOC;
  }
  return $idoc;

}


# method to return a structure object of SAP::Structure type
sub structure {

  my $self = shift;
  my $struct = shift;
  die "RFC is NOT connected for structure discovery!"
     if ! is_connected( $self );
  # do RFC call to obtain structure 
  if ($DEBUG){
    print "RFC CALL for STRUCTURE: $struct \n";
  };
  my $info = $self->sapinfo();

  #warn "digging up structure: $struct\n";
  if ($CACHE && -f $CACHE."/structs/".$struct.".txt"){
    my $struct1;
	  open(STR, "<$CACHE/structs/".$struct.".txt") or 
	    warn "cant open structure file $CACHE/structs/".$struct.".txt - $!";
	  $struct = join("",(<STR>));
	  close STR;
	  eval($struct);
	  $struct1->{'RFCINTTYP'} = $info->{'RFCINTTYP'};
	  $struct1->{'LINTTYP'} = $self->{'LINTTYP'};
    #$struct1->{'SYSINFO'} = $info;
    my $type = MyInstallStructure($self->{'HANDLE'}, {NAME => $struct1->name, DATA => $struct1->fieldinfo});
		#warn "reinstalled: $type\n";
    $struct1->StrType($type);
	  return $struct1;
  }

# if UNICODE RFC_GET_UNICODE_STRUCTURE
#  my $iface;
#  if ($self->{'UNICODE'}){
#    $iface = {
#      'TABNAME' => { 'TYPE' => int(RFCEXPORT),
#	    'VALUE' => $struct,
#	    'INTYPE' => RFCTYPE_CHAR,
#	    'LEN' => length($struct) }, 
#      'FIELDS'    => { 'TYPE' => int(RFCTABLE),
#	    'VALUE' => [],
#	    'INTYPE' => RFCTYPE_BYTE,
#	    'LEN' => 93 } 
#    };
#  } else {
#    $iface = {
#      'TABNAME' => { 'TYPE' => int(RFCEXPORT),
#	    'VALUE' => $struct,
#	    'INTYPE' => RFCTYPE_CHAR,
#	    'LEN' => length($struct) }, 
#      'FIELDS'    => { 'TYPE' => int(RFCTABLE),
#	    'VALUE' => [],
#	    'INTYPE' => RFCTYPE_BYTE,
#	    'LEN' => 83 } 
#    }; 
#  }

#  my $str = MyRfcCallReceive( $self->{'HANDLE'},
#			      $self->{'UNICODE'} ? "RFC_GET_UNICODE_STRUCTURE" : 
#                                 "RFC_GET_STRUCTURE_DEFINITION_P",
#			      $iface );
#  
#  if ($str->{'__RETURN_CODE__'} ne '0') {
#  	$self->{ERROR} = $str->{'__RETURN_CODE__'};
#	  return undef;
#  }

  my $data = MyGetStructure($self->{'HANDLE'}, $struct);
	my $tablen = pop(@{$data});
	if ($self->unicode){
	  $tablen = $tablen->{'b2len'};
	} else {
	  $tablen = $tablen->{'tablength'};
	}

  $struct = SAP::Struc->new( NAME => $struct, RFCINTTYP => $info->{'RFCINTTYP'}, LINTTYP => $self->{'LINTTYP'}, LEN => $tablen );
#  map {
#      my ($tabname, $field, $pos, $off, $intlen, $decs, $exid );
#      if ($self->{'UNICODE'}){
#        my $rec = $_;
#        #warn "unpack($pack_str) \n";
#        ($tabname, $field, $pos, $exid, $decs, $off, $intlen) =
#         (substr($rec, 0, 30), substr($rec, 30, 30), substr($rec, 60, 4),
#          substr($rec, 64, 1), substr($rec, 68, 4), substr($rec, 72, 4), 
#          substr($rec, 76, 4));
#         #$pos = substr($rec, 0, 30);
#         #$pos = substr($rec, 30, 30);
#         #$pos = substr($rec, 60, 4);
#         #$decs = substr($rec, 68, 4);
#         #$off = substr($rec, 72, 4);
#         #$intlen = substr($rec, 76, 4);
#         ($pos, $off, $intlen, $decs) = 
#             map { unpack(($self->{'RFCINTTYP'} eq 'BIG' ? "N" : "V"), $_) }
#                   ($pos, $off, $intlen, $decs);
#      } else {
#        ($tabname, $field, $pos, $off, $intlen, $decs, $exid ) =
## record structure changes from 3.x to 4.x
#       	  unpack( ( $info->{RFCSAPRL} =~ /^[4-9]\d\w\s$/ ) ?
#		         "A30 A30 A4 A6 A6 A6 A" : "A10 A10 A4 A6 A6 A6 A", $_ );
#      }
#      #warn "field: $field - pos: $pos - len: $intlen - offset: $off - dec: $decs \n";
#      $struct->addField( 
#			 NAME     => $field,
# 			 LEN      => $intlen,
##			 add UNICODE Support
##      LEN      => ( $self->{'UNICODE'} ? int($intlen)/2 : int($intlen) ),
# 			 OFFSET   => $off,
##      OFFSET   => ( $self->{'UNICODE'} ? int($off)/2 : int($off) ),
#			 DECIMALS => $decs,
#			 INTYPE   => $exid
#			 )
#      }  ( @{ $str->{'FIELDS'} } );
  #$struct->{'SYSINFO'} = $info;
  map {
	    if ($self->unicode) {
        $struct->addField( 
			   NAME     => $_->{'fieldname'},
 			   LEN      => $_->{'len1'},
 			   OFFSET   => $_->{'off1'},
			   DECIMALS => $_->{'dec'},
			   INTYPE   => $_->{'exid'},
			   EXID     => $_->{'exid'},
 			   LEN2     => $_->{'len2'},
 			   OFFSET2  => $_->{'off2'},
 			   LEN4     => $_->{'len4'},
 			   OFFSET4  => $_->{'off4'}
			   )
			} else {
			  # hack for bad structure issues with type L
				# should be type C ?
	      $_->{'exid'} = "C" if $_->{'exid'} eq "L";
        $struct->addField( 
			   NAME     => $_->{'fieldname'},
 			   LEN      => $_->{'len'},
 			   OFFSET   => $_->{'off'},
			   DECIMALS => $_->{'dec'},
			   EXID     => $_->{'exid'},
			   INTYPE   => $_->{'exid'}
			   )
			 }
      }  ( @{$data} );

  #print STDERR Dumper($struct)."\n";
  # save the structure to the cache
  if ($CACHE){
    open(STR, ">$CACHE/structs/".$struct->name().".txt") or
      warn "cant open cache file for $CACHE/".$struct->name().".txt - $!\n";
    $Data::Dumper::Varname = 'struct';
    print STR Dumper($struct);
    close STR;
  }

  my $type = MyInstallStructure($self->{'HANDLE'}, {NAME => $struct->name, DATA => $struct->fieldinfo});
#	print STDERR "Structure: ".$struct->name." type: $type \n";
  $struct->StrType($type);

  return $struct;

}

#  get the handle
sub handle {

  my $self = shift;
  return  $self->{'HANDLE'};
  
}



#  test the open connection status
sub is_connected {

  my $self = shift;

#	my $ping;
#	if ($self->unicode){
#    #$ping = MyRfcCallReceive( $self->{'HANDLE'}, $self->u8to16("RFC_PING"), {} );
#    $ping = MyRfcCallReceive( $self->{'HANDLE'}, do_8to16("RFC_PING"), {} );
#	} else {
#    $ping = MyRfcCallReceive( $self->{'HANDLE'}, "RFC_PING", {} );
#  }
#  if ($ping->{'__RETURN_CODE__'} eq '0') {
#  	return 1;
#  } else {
#  	$self->{'ERROR'} = $ping->{'__RETURN_CODE__'};
#  	return undef;
#  }

  if (MyRfcPing($self->{'HANDLE'})){
  	return 1;
	} else {
  	return undef;
	}
  
}

# Call The RFCSI_EXPORT Function module to
#  get the instance information of the connected system
sub sapinfo {
  my $return = "";
  my $output = "";

  my $self = shift;
  # delete  $self->{'SYSINFO'};

  if ( ! exists $self->{'SYSINFO'} ){
    die "SAP Connection Not Open for SYSINFO "
      if ! is_connected( $self );
#    my $if;
##		if ($self->unicode){
##      $if = {   'RFCSI_EXPORT' => {
##                #'NAME' => $self->u8to16('RFCSI_EXPORT'),
##                'NAME' => do_8to16('RFCSI_EXPORT'),
##				        'TYPE' => int(RFCIMPORT),
##				        'VALUE' => '',
##				        'INTYPE' => RFCTYPE_CHAR,
##				        'LEN' => 400 }
##				  };
##		} else {
#      $if = {   'RFCSI_EXPORT' => {
#				        'TYPE' => int(RFCIMPORT),
#				        'VALUE' => '',
#				        'INTYPE' => RFCTYPE_CHAR,
#				        'LEN' => $self->unicode ? 400 : 200 }
#				  };
##		}
#    my $sysinfo = MyRfcCallReceive( $self->{'HANDLE'}, 
##		                 #($self->unicode ? $self->u8to16("RFC_SYSTEM_INFO") : "RFC_SYSTEM_INFO"),
##		                 ($self->unicode ? do_8to16("RFC_SYSTEM_INFO") : "RFC_SYSTEM_INFO"),
#		                 "RFC_SYSTEM_INFO",
#										 $if );
#    if ($sysinfo->{'__RETURN_CODE__'} ne '0') {
#  	  $self->{ERROR} = $sysinfo->{'__RETURN_CODE__'};
#	    return {};
#    }
    my $rfcsi = MySysinfo($self->{'HANDLE'});
    my $pos = 0;
    my $info = {};
		#map { print STDERR "key: $_ => ".length($sysinfo->{$_})."\n" } keys %$sysinfo;
#    my $rfcsi = $sysinfo->{'RFCSI_EXPORT'};
#		if ($self->unicode){
#		  #$rfcsi = $self->u16to8($rfcsi);
#		  $rfcsi = do_16to8($rfcsi);
#		}
    map {
	  $info->{$_->{'NAME'}} = substr($rfcsi,$pos, $_->{'LEN'});
	  $pos += $_->{'LEN'}
            } @SYSINFO;
    $self->{'RETURN'} = 0;
    $self->{'SYSINFO'} = $info;

#   add UNICODE Support
#    $self->{'UNICODE'} = 1 if ( int($info->{'RFCCHARTYP'}) >> 1  == 2051 );
  }
  return  $self->{'SYSINFO'};
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

  my $result = MyRfcCallReceive( $self->{'HANDLE'}, $iface->name, $iface->iface );

#	print STDERR "AFTER CALL: ".Dumper($result)."\n";
  
  if ( $result->{'__RETURN_CODE__'} ne "0" ){
      $self->{'ERROR'} = $result->{'__RETURN_CODE__'};
      die "RFC call failed: ".$result->{'__RETURN_CODE__'};
  } else {
      map { 
      	  $_->intvalue(intoext($_, $result->{$_->name()})) unless $_->type() == RFCEXPORT
	          } ( $iface->parms() );
      $iface->emptyTables();
      map { my $tab = $_;
	      map { $tab->addRow( $_ ) } ( @{$result->{$tab->name()}} )
	           } ( $iface->tabs() );
  }
}


# Get the logon ticket
sub getTicket {
  my $self = shift;

  die "SAP Connection Not Open for Ticket retrieval "
     if ! is_connected( $self );

  my $result = MyGetTicket($self->{'HANDLE'});
  
  if ( $result->{'__RETURN_CODE__'} ne "0" ){
      $self->{'ERROR'} = $result->{'__RETURN_CODE__'};
      die "RFC call failed: ".$result->{'__RETURN_CODE__'};
  } else {
	    return $result->{'TICKET'};
  }
}


# convert internal data types to externals
sub intoext{
  my $parm = shift;
  my $value = shift || "";

  if ( $parm->intype() == RFCTYPE_INT ){
	  return unpack("l", $value);
  } elsif ( $parm->intype() == RFCTYPE_FLOAT ){
	  return unpack("d",$value);
	} elsif ( $parm->intype() == RFCTYPE_INT2 ){ 
	  # Short INT2
    return unpack("S",$value);
  } elsif ( $parm->intype() == RFCTYPE_INT1 ){
    # INT1
    return ord($value);
  } elsif ( $parm->intype() == RFCTYPE_BCD ){
	#  All types of BCD
	  $value = "0" unless $value;
	  my @flds = split(//, unpack("H*",$value));
		#print STDERR "BCD VALUE ".$parm->name.": ".unpack("H*",$value)."\n";
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
  if ( exists $self->{'HANDLE'} ) {
      MyDisconnect( $self->{'HANDLE'} );
      delete $self->{'HANDLE'};
      delete $self->{'SYSINFO'};
      return 1;
  } else {
      return undef;
  };
}


# Return error message
sub error {
  my $self = shift;
  my $msg = $self->{'ERROR'};
  $msg =~ s/^.+MESSAGE\s*//;
  return $msg;
}


# Return error detailed
sub errorKeys {
  my $self = shift;
  my $msg = { split(/\t/, $self->{'ERROR'}) };
  return $msg;
}



=head1 NAME

SAP::Rfc - SAP RFC - RFC Function calls against an SAP R/3 System

=head1 SYNOPSIS

  # WARNING - as of SAP::Rfc 1.40 USER and PASSWD are case sensitive ready for 
  # R3 7.x
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

  # or pass a list of hash refs like so:
  $it->OPTIONS( [ { TEXT => "NAME LIKE 'RS%'" } ] );

  $rfc->callrfc( $it );

  print "NO. PROGS: ".$it->tab('DATA')->rowCount()." \n";
  print join("\n",( $it->DATA ));

  $rfc->close();



=head1 DESCRIPTION

SAP::Rfc - is a Perl extension for performing RFC Function calls against an SAP R/3 System.  Please refer to the README file found with this distribution.  This Distribution also allows the creation of registered RFCs so that an SAP system can call arbitrary Perl code created in assigned callbacks.

The best way to describe this package is to give a brief over view, and then launch into several examples.  The SAP::Rfc package works in concert with several other packages that also come with same distribution, these are SAP::Iface, SAP::Parm, SAP::Tab, and SAP::Struc.  These come together to give you an object oriented programming interface to performing RFC function calls to SAP from a UNIX based platform with your favourite programming language - Perl.  A SAP::Rfc object holds together one ( and only one ) connection to an SAP system at a time.  The SAP::Rfc object can hold one or many SAP::Iface objects, each of which equate to the definition of an RFC Function in SAP ( trans SE37 ). Each SAP::Iface object holds one or many SAP::Parm, and/or SAP::Tab objects, corresponding to the RFC Interface definition in SAP ( SE37 ).

For all SAP::Tab objects, and for complex SAP::Parm objects, a SAP::Struc object can be defined.  This equates to a structure definition in the data dictionary ( SE11 ).  Because the manual definition of interfaces and structures is a boring and tiresome exercise, there are specific methods provided to automatically discover, and add the appropriate interface definitions for an RFC Function module to the SAP::Rfc object ( see methods discover, and structure of SAP::Rfc ).

Please note that USER and PASSWD are now case sensitive - this change has the potential to break backward compatibility.


=head1 METHODS:

=head2 PARAM_NAME()

  $rfc->PARM_NAME( 'a value ')

  The parameter or tables can be accessed through autoloaded method calls
  - this can be useful for setting or getting the parameter values.

=head2 discover()

  $iface = $rfc->discover('RFC_READ_REPORT');
  Discover an RFC interface definition, and automaticlly add it to an 
  SAP::Rfc object.  This will also define all associated SAP::Parm, 
  SAP::Tab, and SAP::Struc objects.


=head2 structure()

  $str = $rfc->structure('QTAB');
  Discover and return the definition of a valid data dictionary 
  structure.  This could be subsequently used with an SAP::Parm, or 
  SAP::Tab object.



=head2 is_connected()

  if ($rfc->is_connected()) {
  } else {
  };
  Test that the SAP::Rfc object is connected to the SAP system.


=head2 sapinfo()

  %info = $rfc->sapinfo();
  map { print "key: $_ = ", $info{$_}, "\n" }
        sort keys %info;
  Return a hash of the values supplied by the RFC_SYSTEM_INFO 
  function module.  This function is only properly called once, and
  the data is cached until the RFC connection is closed - then it 
  will be reset next call.
  


=head2 callrfc()

  $rfc->callrfc($iface);
  Do the actual RFC call - this installs all the Export, Import, and
  Table Parameters in the actual C library of the XS extension, does
  the RFC call, Retrieves the table contents, and import parameter
  contents, and then cleans the libraries storage space again.


=head2 getTicket()

	This is for using SAP Logon Tickets, generated by your R/3 system.

  retrieve the requested ticket:
  $rfc = new SAP::Rfc(
		      ASHOST   => 'myhost',
		      USER     => 'ME',
		      PASSWD   => 'secret',
		      GETSSO2   => 1,
		      LANG     => 'EN',
		      CLIENT   => '200',
		      SYSNR    => '00',
		      TRACE    => '1' );
  my $ticket = $rfc->getTicket();

  The ticket can then be used to do logins like so:
  $rfc = new SAP::Rfc(
		      ASHOST   => 'myhost',
		      MYSAPSSO2   => $ticket,
		      LANG     => 'EN',
		      CLIENT   => '200',
		      SYSNR    => '00',
		      TRACE    => '1' );


=head2 close()

  $rfc->close();
  Close the current open RFC connection to an SAP system, and then 
  reset cached sapinfo data.


=head2 error()

  $rfc->error();
  Returns error string if previous call returned undef (currently 
  supported for discover, structure, is_connected and sapinfo).


=head2 errorKeys()

  $rfc->errorKeys();
  Returns a hash of all the RFC error components as found in the standard
  RFC trace file:
  $VAR1 = {
          'KEY' => 'RFC_ERROR_SYSTEM_FAILURE',
          'GROUP' => '104',
          'EXCEPT' => 'SYSTEM_FAILURE',
          'MESSAGE' => 'Name or password is incorrect. Please re-enter'
      };
  Is an example of a login faliure.


=head2 accept()

This is the main function to initiate a registered RFC. Consider this
example that implements the same functionality as the standard rfcexec
executable that comes with all SAP R/3 server implementations:

  use SAP::Rfc;
  use SAP::Iface;
  use Data::Dumper;

  # this enables the user to call die "MY_CUSTOM_ERROR"
  # and only the string MY_CUSTOMER_ERROR is returned to SAP instead of
  # the whole die text + line number etc.
  $SAP::Rfc::EXCEPTION_ONLY = 1;

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
    # force an error
    die "MY_CUSTOM_ERROR" unless $iface->PIPEDATA;
    return 1;
  }

  If accept() returns a defined value then the $rfc->error() can be 
  checked for an associated error message.

  accept() takes a two parameters \&callback(), and $wait.  \&callback()
  is a subroutine reference that will be called each time an event has happened
  within the accept loop.  If an RFC is called then the callback is made
  after the RFC callback has been executed, otherwise the callback is made
  after the accept timeout has been reached.  $wait specifies the time 
  to wait in the accept loop before breaking to execute the callback
  function.  If no wait interval is specified, then a default of
  10 seconds is specified.
  callback() must return true (Perl true) all RFC_SYS_EXCEPTION is set, and the
  accept() loop exits.


=head2 accept() with tRFC ... continued

  tRFC must be activated by passing parameters to the $rfc = new SAP::Rfc( ... );
  tRFC cannot be performed at the same time as standard registered RFC, do to the 
  behaviour inside the main event loop.

  Build the tRFC server connection like this:

  my $rfc = new SAP::Rfc(
             TRFC           => 1,
             TRFC_CHECK     => \&do_my_tid_check,
             TRFC_CONFIRM   => \&do_my_tid_confirm,
             TRFC_ROLLBACK  => \&do_my_tid_rollback,
             TRFC_COMMIT    => \&do_my_tid_commit,
             TPNAME         => 'wibble.rfcexec',
             GWHOST         => 'seahorse.local.net',
             GWSERV         => '3300',
             TRACE          => '1' );

  TRFC => 1 - activates the installation of the tRFC transaction control.
  TRFC_CHECK, TRFC_CONFIRM, TRFC_ROLLBACK, TRFC_COMMIT are parameters that
  override the default callback functions for tRFC transaction control.
  consult the saprfc.h header file of the rfcsdk for the full details.
  TRFC_CHECK is the only one that can return a value - it returns true
  if this is a new transaction to be processed, or false to reject the 
  transaction.  All other TRFC_* callbacks return void().

  In the actual callback() for each registered RFC in tRFC mode, there is
  an additional parameter passed for the tRFC transaction id (tid):
  sub do_remote_pipe {
    my $iface = shift;
    my $tid = shift;
    ...

  This can be used to track the status of the callback success, and relay
  this information to the other transaction control callback (TID_*).


=head2 allow_start_program("; separated list of programs")

  With that the Method it is possible to launch a program. This feature is
  hevealy used by SAP DMS (Document Management System) which sends and
  receives Files from and to the client.


=head2 register()

This is the equivalent to accept() but allows you to process the 
main event loop one step at a time.  This must be used with process() and 
close() to mange the loop processing manually.
example that implements the same functionality as the standard rfcexec
executable that comes with all SAP R/3 server implementations:

  use SAP::Rfc;
  use SAP::Iface;
  use Data::Dumper;

  # this enables the user to call die "MY_CUSTOM_ERROR"
  # and only the string MY_CUSTOMER_ERROR is returned to SAP instead of
  # the whole die text + line number etc.
  $SAP::Rfc::EXCEPTION_ONLY = 1;

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
  my $handle = $rfc->register();

  while ($rc = $rfc->process($handle, $wait)){
	  if ($rc != 0){
		  warn "Eeek! it went wrong!\n";
			exit(1);
		}
    ...
	}

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
    # force an error
    die "MY_CUSTOM_ERROR" unless $iface->PIPEDATA;
    return 1;
  }

  If register() returns a value less than 0 then it failed.
	If process() returns a value other than 0 then it failed.
  register() takes no parameters, but returns the created RFC handle.
  process() takes two parameters - $handle typically returned from register(), 
	and $wait.


=head2 CACHING
  
  Activate the caching of Interface and Structure definitions (generated via
  SAP::Rfc->discover() and SAP::Rfc->structure()).  The definitions are 
  serialized/deserialised using Data::Dumper, which has the effect of 
  speeding up the startup times of scripts (you nolonger have to the SAP
  system everytime you need get a reference to the cached definitions).  If 
  you enable caching then you need to be careful about differences in byte
  order between systems you communicate with (same definitions are retrieved 
  regardless of system connected to), and the potential differences in 
  interface/structure definitions between your systems (perhaps because of
  release etc.).
 
    $SAP::Rfc::USECACHE = 1;
 
  The default cache is set to ".rfc_cache/".  If you don't like the default 
  then you need to change this by setting $SAP::Rfc::CACHE to a directory of
  your choice.



=head1 AUTHOR

Piers Harding, piers@ompa.net.

But Credit must go to all those that have helped.


=head1 SEE ALSO

perl(1), SAP::Iface(3).

=cut


1;
