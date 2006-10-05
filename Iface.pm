package SAP::Iface;

use strict;

require 5.005;
use  Encode;

use vars qw($VERSION $AUTOLOAD);

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

# Valid parameters
my $IFACE_VALID = {
   NAME => 1,
   UNICODE => 1,
   ENDIAN => 1,
   HANDLER => 1,
   PARAMETERS => 1,
   TABLES => 1,
   EXCEPTIONS => 1,
   SYSINFO => 1,
   RFCINTTYP => 1,
   LINTTYP => 1
};

$VERSION = '1.53';

# empty destroy method to stop capture by autoload
sub DESTROY {
}

# work arround for the VERSION interface parameter
sub VERSION {
  my $self = shift;
  my $name = 'VERSION';
  if ( exists $self->{PARAMETERS}->{uc($name)} ) {
      &parm($self, $name)->value( @_ );
  } elsif ( exists $self->{TABLES}->{uc($name)} ) {
      &tab($self, $name)->rows( @_ );
  } else {
      die "Parameter $name does not exist in Interface - no autoload";
  };
}

sub AUTOLOAD {

  my $self = shift;
  my @parms = @_;
  my $type = ref($self)
          or die "$self is not an Object in autoload of Iface";
  my $name = $AUTOLOAD;
  $name =~ s/.*://;

# Autoload constants

 if ( uc($name) eq 'RFCEXPORT' ) {
      return RFCEXPORT;
  } elsif ( uc($name) eq 'RFCIMPORT' ) {
      return RFCIMPORT;
  } elsif ( uc($name) eq 'RFCTABLE' ) {
      return RFCTABLE;
  } elsif ( uc($name) eq 'RFCTYPE_CHAR' ) {
      return RFCTYPE_CHAR;
  } elsif ( uc($name) eq 'RFCTYPE_BYTE' ) {
      return RFCTYPE_BYTE;
  } elsif ( uc($name) eq 'RFCTYPE_DATE' ) {
      return RFCTYPE_DATE;
  } elsif ( uc($name) eq 'RFCTYPE_TIME' ) {
      return RFCTYPE_TIME;
  } elsif ( uc($name) eq 'RFCTYPE_BCD' ) {
      return RFCTYPE_BCD;
  } elsif ( uc($name) eq 'RFCTYPE_NUM' ) {
      return RFCTYPE_NUM;
  } elsif ( uc($name) eq 'RFCTYPE_FLOAT' ) {
      return RFCTYPE_FLOAT;
  } elsif ( uc($name) eq 'RFCTYPE_INT' ) {
      return RFCTYPE_INT;
  } elsif ( uc($name) eq 'RFCTYPE_INT2' ) {
      return RFCTYPE_INT2;
  } elsif ( uc($name) eq 'RFCTYPE_INT1' ) {
      return RFCTYPE_INT1;
# Autoload parameters and tables
  } elsif ( exists $self->{PARAMETERS}->{uc($name)} ) {
      &parm($self, $name)->value( @_ );
  } elsif ( exists $self->{TABLES}->{uc($name)} ) {
      &tab($self, $name)->rows( @_ );
  } else {
      die "Parameter $name does not exist in Interface - no autoload";
  };
}


# Construct a new SAP::Iface object
sub new {

  my $proto = shift;
  my $class = ref($proto) || $proto;

  @_ = ('NAME' => @_) if scalar @_ == 1;
  my $self = {
	   ENDIAN => join(" ", map { sprintf "%#02x", $_ } unpack("C*",pack("L",0x12345678))) eq "0x78 0x56 0x34 0x12" ? "LIT" : "BIG",
  	PARAMETERS => {},
  	TABLES => {},
  	EXCEPTIONS => {},
  	SYSINFO => {},
	@_
  };

    die "No RFC Name supplied to Interface !" if ! exists $self->{NAME};

# Validate parameters
  map { delete $self->{$_} if ! exists $IFACE_VALID->{$_} } keys %{$self};
  $self->{NAME} = $self->{NAME};

# create the object and return it
  bless ($self, $class);
  return $self;
}


# get the name
sub name {
  my $self = shift;
  return $self->{NAME};
}


# get the sysinfo of the current connection 
# only relevent for registered RFC
sub sysinfo {
  my $self = shift;
  return $self->{'SYSINFO'};
}


# set/get the handler
sub handler {
  my $self = shift;
  $self->{'HANDLER'} = shift @_ 
       if scalar @_ == 1;
  return $self->{'HANDLER'};
}


# Add an export parameter Object
sub addParm {

  my $self = shift;
  die "No parameter supplied to Interface !" if ! @_;
  my $parm;
  if (my $ref = ref($_[0])){
      die "This is not an Parameter for the Interface - $ref ! "
	  if $ref ne "SAP::Parms";
      $parm = $_[0];
  } else {
      $parm = SAP::Parms->new( @_ );
  };

  return $self->{PARAMETERS}->{$parm->name()} = $parm;
}


# Access the export parameters
sub parm {
  my $self = shift;
  die "No parameter name supplied for interface" if ! @_;
  my $parm = uc(shift);
  die "Parameter $parm Does not exist in interface !"
           if ! exists $self->{PARAMETERS}->{$parm};
  return $self->{PARAMETERS}->{$parm};
}


# Return the parameter list
sub parms {
  my $self = shift;
  return sort { $a->name() cmp $b->name() } values %{$self->{PARAMETERS}};
}


# Return the parameter list excluding empty export parameters
sub parms_noempty {
  my $self = shift;
  return sort { $a->name() cmp $b->name() } grep { ! ($_->type() == RFCEXPORT && ! $_->changed()) }values %{$self->{PARAMETERS}};
}


# Add an Table Object
sub addTab {
  my $self = shift;
  die "No Table supplied for interface !" if ! @_;
  my $table;
  if ( my $ref = ref($_[0]) ){
      die "This is not a Table for interface: $ref ! "
	  if $ref ne "SAP::Tab";
      $table = $_[0];
  } else {
      $table = SAP::Tab->new( @_ );
  };
  return $self->{TABLES}->{$table->name()} = $table;
}


# Is this a Table parameter
sub isTab {
  my $self = shift;
  my $table = uc(shift);
     return exists $self->{TABLES}->{ $table } ? 1 : undef;
}


# Access the Tables
sub tab {
  my $self = shift;
  die "No Table name supplied for interface" if ! @_;
  my $table = uc(shift);
  die "Table $table Does not exist in interface  !"
     if ! exists $self->{TABLES}->{ $table };
  return $self->{TABLES}->{ $table };
}


# Return the Table list
sub tabs {
  my $self = shift;
  return sort { $a->name() cmp $b->name() } values %{$self->{TABLES}};
}


# Empty The contents of all tables in an interface
sub emptyTables {
  my $self = shift;
  map { $_->empty(); } ( $self->tabs() );
  return 1;
}



# Add an Exception code
sub addException {
  my $self = shift;
  die "No exception parameter supplied to Interface !" if ! @_;
  my $exception = uc(shift);
  return $self->{EXCEPTIONS}->{$exception} = $exception;
}


# Check Exception Exists
sub exception {
  my $self = shift;
  die "No Exception parameter name supplied for interface" if ! @_;
  my $exception = uc(shift);
  return ( ! exists $self->{EXCEPTIONS}->{ $exception } ) ? $exception : undef;
}


# Return the Exception parameter list
sub exceptions {
  my $self = shift;
  return sort keys %{$self->{EXCEPTIONS}};
}


# Reset the entire interface
sub reset {
  my $self = shift;
  #  Reset all the tables
  emptyTables( $self );
  # Reset all parameters
  map { $_->value( $_->default ); } ( parms() );
  return 1;
}


#Generate the Interface hash
sub iface {

    my $self = shift;
    my $flag = shift || "";

    my $iface = {};
    map { $iface->{$_->name()} = { 'TYPE' => $_->type(),
	                           'INTYPE' => $_->intype(),
				                     'DATA' => ($_->structure ? [$_->data() ] : undef),
#                                   'VALUE' => ((($_->intype() == RFCTYPE_BYTE) && $_->type() == RFCEXPORT ) ? pack("A".$_->leng(), $_->intvalue()) : ($self->unicode && $_->structure ? $_->intvalueparts() : $_->intvalue())),
                                   'VALUE' => ((($_->intype() == RFCTYPE_BYTE) && $_->type() == RFCEXPORT ) ? pack("A".$_->leng(), $_->intvalue()) : $_->intvalue()),
#                                   'LEN' => ((($_->intype() == RFCTYPE_CHAR) && $_->type() != RFCIMPORT ) ? length($_->intvalue()) : $_->leng()) }
                                   'LEN' => ((($_->intype() == RFCTYPE_CHAR) && $_->type() != RFCIMPORT && ! $_->unicode ) ? length($_->intvalue()) : $_->leng()) }
      } ( $flag ? $self->parms : $self->parms_noempty() );

    map { $iface->{$_->name()} = { 'TYPE' => RFCTABLE,
	                           'INTYPE' => $_->intype(),
#				   'VALUE' => [ ($self->unicode ? $_->introws() : $_->rows()) ],
				   'VALUE' => [ $_->introws() ],
				   'DATA' => [$_->data() ],
				   'LEN' => $_->leng() };
      } ( $self->tabs() );

    if ($flag){
      $iface->{'__HANDLER__'} = $self->{'HANDLER'};
      $iface->{'__SELF__'} = $self;
    }
#		use Data::Dumper;
#		print STDERR "Interface to pass in: ".Dumper($iface)."\n";
#		exit(0);
    return $iface;
}

sub unicode {

my $self = shift;
	return $self->{UNICODE};
}


=head1 NAME

SAP::Iface - Perl extension for parsing and creating an Interface Object.  The interface object would then be passed to the SAP::Rfc object to carry out the actual call, and return of values.

=head1 SYNOPSIS

  use SAP::Iface;
  $iface = new SAP::Iface( NAME =>"RFCNAME" );
  NAME is mandatory.

or more commonly:

  use SAP::Rfc;
  $rfc = new SAP::Rfc( ASHOST => ... );
  $iface = $rfc->discover('RFC_READ_REPORT');


=head1 DESCRIPTION

This class is used to construct a valid interface object ( SAP::Iface.pm ).
The constructor requires the parameter value pairs to be passed as 
hash key values ( see SYNOPSIS ). 
Generally you would not create one of these manually as it is far easier to use the "discovery" functionality of the SAP::Rfc->discover("RFCNAME") method.  This returns a fully formed interface object.  This is achieved by using standard RFCs supplied by SAP to look up the definition of an RFC interface and any associated structures.

=head1 METHODS

=head2 new()

  use SAP::Iface;
  $iface = new SAP::Iface( NAME =>"RFC_READ_TABLE" );
  Create a new Interface object.


=head2 PARM_NAME()

  $iface->PARM_NAME(' new value ')
  Parameters and tables are autoloaded methods - than can be accessed 
  like this to set and get their values.


=head2 RFCTYPE_CHAR()

  Autoloaded methods are provided for all the constant definitions 
  relating to SAP parameter types.


=head2 name()

  Return the name of an interface.

=head2 addParm()

  $iface->addParm(
                 TYPE => SAP::Iface->RFCEXPORT,
                 INTYPE => SAP::Iface->RFCTYPE_CHAR,
                 NAME => 'A_NAME', 
                 STRUCTURE =>
                    $rfc->structure('NAME_OF_STRUCTURE'), 
                 DEFAULT => 'the default value',
                 VALUE => 'the current value',
                 DECIMALS => 0,
                 LEN => 20 );
  Add an RFC interface parameter to the SAP::Iface definition 
  - see SAP::Parm.


=head2 parm()

  $iface->parm('PARM_NAME');
  Return a reference to a named parameter object.

=head2 parms()

  Return a list of parameter objects for an interface.

=head2 addTab()

  $iface->addTab(
                INTYPE => SAP::Iface->RFCTYPE_BYTE, 
                 NAME => 'NAME_OF_TABLE',
                 STRUCTURE =>
                     $rfc->structure('NAME_OF_STRUCTURE'), 
                 LEN => 35 );
  Add an RFC interface table definition to the SAP::Iface object 
    - see SAP::Tab.


=head2 isTab()

  $iface->isTab('TAB_NAME');
  Returns true if the named parameter is a table.


=head2 tab()

  $iface->tab('TAB_NAME');
  Return a reference to the named table object - see SAP::Tab.

=head2 tabs()

  Return a list of table objects for the SAP::Iface object.

=head2 emptyTables()

  Empty the contents of all the tables on a SAP::Iface object.


=head2 addException()

  $iface->addException('EXCEPTION_NAME');
  Add an exception name to the interface.

=head2 exception()

  $iface->exception('EXCEPTION_NAME');
  Return the named exception name - basically I dont do anything with 
  exceptions yet except keep a list of names that could be checked
  against an RFC failure return code.

=head2 exceptions()

  Return a list of exception names associated with a SAP::Iface object.

=head2 reset()

  Empty all the tables and reset paramters to their default values - 
  useful when you are doing multiple calls.

=head2 iface()

  An internal method that generates the internal structure passed into 
  the C routines.

=head2 handler()

  return a reference to the callback handler for registered RFC 

=head2 sysinfo()

  return a hash ref containing the system info for the current 
  registered RFC callback


=cut

package SAP::Tab;

use strict;
use vars qw($VERSION);


# Globals

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


# Valid parameters
my $TAB_VALID = {
   VALUE => 1,
   NAME => 1,
   ENDIAN => 1,
   UNICODE => 1,
   RFCINTTYP => 1,
   INTYPE => 1,
   LEN => 1,
   STRUCTURE => 1
};


# Valid data types
my $TAB_VALTYPE = {
   RFCTYPE_CHAR, RFCTYPE_CHAR,
   RFCTYPE_BYTE, RFCTYPE_BYTE,
   RFCTYPE_BCD,  RFCTYPE_BCD,
   RFCTYPE_DATE, RFCTYPE_DATE,
   RFCTYPE_TIME,  RFCTYPE_TIME,
   RFCTYPE_NUM, RFCTYPE_NUM,
   RFCTYPE_INT, RFCTYPE_INT,
   RFCTYPE_INT2, RFCTYPE_INT2,
   RFCTYPE_INT1, RFCTYPE_INT1,
   RFCTYPE_FLOAT, RFCTYPE_FLOAT
};


# Construct a new SAP::Table object.
sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self = {
	   ENDIAN => join(" ", map { sprintf "%#02x", $_ } unpack("C*",pack("L",0x12345678))) eq "0x78 0x56 0x34 0x12" ? "LIT" : "BIG",
     VALUE => [],
     INTYPE => RFCTYPE_BYTE,
     @_
  };

  die "Table Name not supplied !" if ! exists $self->{NAME};
  die "Table $self->{NAME} Length not supplied !" if ! exists $self->{LEN};

# Validate parameters
  map { delete $self->{$_} if ! exists $TAB_VALID->{$_} } keys %{$self};
  $self->{NAME} = uc($self->{NAME});

# create the object and return it
  bless ($self, $class);
  return $self;
}


sub unicode {
  my $self = shift;
  return $self->{UNICODE};
}


# Set/get the table rows - pass a reference to a anon array
sub rows {
  my $self = shift;
  if (@_){
    $self->{'VALUE'} = shift;
    my @rows = ();
    my $str = $self->structure();
		my $flds = $str->fieldinfo;
    foreach my $row ( @{$self->{'VALUE'}} ){
		if ($self->unicode){
		  # we must be given a hash
      die "in Unicode a parameter ($self->{NAME}) must be passed a HASH"
			  unless ref($row) eq 'HASH';
			my $line = [];
      map { 
			  my $fld = $_;
				my $value = $row->{$fld->{fieldname}};
        if ( $fld->{intype} == RFCTYPE_BCD){
	        $value =~ s/^\s+([ -+]\d.*)$/$1/;
	        $value ||= 0;
	        $value = sprintf("%0".int(($fld->{len1}*2) + ($fld->{dec} > 0 ? 1:0)).".".$fld->{dec}."f", $value);
	        $value =~ s/\.//g;
	        my @flds = split(//, $value);
	        shift @flds eq '-' ? push( @flds, 'd'): push( @flds, 'c');
	        $value = join('', @flds);
          $value = pack("H*", $value);
        } elsif ( $fld->{intype} == RFCTYPE_FLOAT){
  	      $value = pack("d", $value);
        } elsif ( $fld->{intype} == RFCTYPE_INT){
  	      $value = pack(($self->{'ENDIAN'} eq "BIG" ? "l" : "V" ), int($value));
        } elsif ( $fld->{intype} == RFCTYPE_INT2){
  	      $value = pack("S", int($value));
        } elsif ( $fld->{intype} == RFCTYPE_INT1){
        # get the last byte of the integer
  				$value = chr(int($value));
        } elsif ( $fld->{intype} == RFCTYPE_DATE){
  				$value ||= '00000000';
        } elsif ( $fld->{intype} == RFCTYPE_TIME){
  				$value ||= '000000';
        } else {
				  # This is a char type - sort out unicode
					$value ||= " ";
					{
            use utf8;
            Encode::_utf8_on($value);
            if (length($value) > $fld->{len1}){
              $value = substr($value, 0, $fld->{len1});
            } else {
              $value = pack("A".$fld->{len1}, $value);
            }
            Encode::_utf8_off($value);
            no utf8;
					}
        };
				push(@{$line}, $value);
			} ( @{$flds} );
      push(@rows, $line);
		 } elsif (ref($row) eq 'HASH'){
        map { $str->$_($row->{$_}) } keys %{$row};
	      $row = $str->value;
	      $str->value("");
        push(@rows, $row);
      } else {
        push(@rows, $row);
			}
    }
		if ($self->unicode){
      $self->{'INTVALUE'} = \@rows;
		} else {
      $self->{'VALUE'} = \@rows;
		}
  }
	if ($self->unicode){
	 if ( scalar @{$self->{VALUE}} && ref($self->{VALUE}[0]) eq 'HASH'){ 
	   my @rows = ();
	   map {
		      my $h = $_; 
					my $r = { map { $_ => $h->{$_} } keys %{$h} };
					push(@rows, $r);
					} @{$self->{VALUE}};
		 return @rows;
	 } else {
	  return map { [ map { $_ } @{$_} ] } @{$self->{VALUE}};
	 }
	} else {
    return  map{ pack("A".$self->leng(),$_) } (@{$self->{VALUE}});
  }

}


sub introws {
  my $self = shift;
	if ($self->unicode){
	  return map { [ map { $_ } @{$_} ] } @{$self->{INTVALUE}};
	} else {
    return  map{ pack("A".$self->leng(),$_) } (@{$self->{VALUE}});
  }

}


# retrieve the rows in hashes based on the field names
sub data {
  my $self = shift;
  my @rows = ();
	my $str = $self->structure;
  foreach ( $str->fields() ){
    push ( @rows, [$str->{FIELDS}->{$_}->{INTYPE}, $str->{FIELDS}->{$_}->{OFFSET2}, $str->{FIELDS}->{$_}->{LEN2}]);
  }
  return @rows;
}


# retrieve the rows in hashes based on the field names
sub hashRows {
  my $self = shift;
  my @rows = ();
	if ($self->unicode){
    foreach ( @{$self->{VALUE}} ){ push(@rows, $_); }
	} else {
    foreach ( map{ pack("A".$self->leng(),$_) } (@{$self->{VALUE}}) ){
      $self->structure->value( $_ );
      push ( @rows, { map { $_ => $self->structure->$_() } ( $self->structure->fields ) } );
    }
  }
  return @rows;
}


# Return the next available row from a table
sub nextRow {
  my $self = shift;
  my $row = shift  @{$self->{VALUE}};
  if ( $row ) {
    $self->structure->value( $row );
    return  { map {$_ => $self->structure->$_() } ( $self->structure->fields ) };
  } else {
    return undef;
  }
}


# Set/get the structure parameter
sub structure {
  my $self = shift;
  $self->{STRUCTURE} = shift if @_;
  return $self->{STRUCTURE};
}


# add a row
sub addRow {
  my $self = shift;
  if (@_){
    my $row = shift;
    if (ref($row) eq 'HASH'){
		  if ($self->unicode){
			  my $line = [];
		    my $flds = $self->structure->fieldinfo;
        map { 
			    my $fld = $_;
		  		my $value = $row->{$fld->{fieldname}};
          if ( $fld->{intype} == RFCTYPE_BCD){
	          $value =~ s/^\s+([ -+]\d.*)$/$1/;
	          $value ||= 0;
	          $value = sprintf("%0".int(($fld->{len1}*2) + ($fld->{dec} > 0 ? 1:0)).".".$fld->{dec}."f", $value);
	          $value =~ s/\.//g;
	          my @flds = split(//, $value);
	          shift @flds eq '-' ? push( @flds, 'd'): push( @flds, 'c');
	          $value = join('', @flds);
            $value = pack("H*", $value);
          } elsif ( $fld->{intype} == RFCTYPE_FLOAT){
  	        $value = pack("d", $value);
          } elsif ( $fld->{intype} == RFCTYPE_INT){
  	        $value = pack(($self->{'ENDIAN'} eq "BIG" ? "l" : "V" ), int($value));
          } elsif ( $fld->{intype} == RFCTYPE_INT2){
  	        $value = pack("S", int($value));
          } elsif ( $fld->{intype} == RFCTYPE_INT1){
          # get the last byte of the integer
    				$value = chr(int($value));
          } elsif ( $fld->{intype} == RFCTYPE_DATE){
  			  	$value ||= '00000000';
          } elsif ( $fld->{intype} == RFCTYPE_TIME){
  			  	$value ||= '000000';
          } else {
  				  # This is a char type - sort out unicode
  					$value ||= " ";
  					{
              use utf8;
              Encode::_utf8_on($value);
              if (length($value) > $fld->{len1}){
                $value = substr($value, 0, $fld->{len1});
              } else {
                $value = pack("A".$fld->{len1}, $value);
              }
              Encode::_utf8_off($value);
              no utf8;
  					}
          };
  				push(@{$line}, $value);
  			} ( @{$flds} );
        push(@{$self->{VALUE}}, $line);
			} else {
        map { $self->structure->$_($row->{$_}) } keys %{$row};
        $row = $self->structure->value;
        push(@{$self->{VALUE}}, $row);
			}
    } elsif (ref($row) eq 'ARRAY'){
		  my $cnt = 0;
	    map { $row->[$_->{pos} -1] = substr($row->[$_->{pos} -1], 0, $_->{len1})  } (@{$self->structure->fieldinfo});

      my $line = {};
	    foreach my $fld (@{$self->structure->fieldinfo}){
	  			my $value = $row->[$cnt];
	        #  Transform various packed dta types
          if ( $fld->{intype} eq RFCTYPE_INT ){
        	# Long INT4
            $value = unpack((($self->{'RFCINTTYP'} eq 'BIG')  ? "N" : "V"), $value);
          } elsif ( $fld->{intype} eq RFCTYPE_INT2 ){
        	# Short INT2
            $value = unpack("S",$value);
          } elsif ( $fld->{intype} eq RFCTYPE_INT1 ){
        	# INT1
            $value = ord( $value );
          } elsif ( $fld->{intype} eq RFCTYPE_NUM ){
        	# NUMC
            $value = int($value);
          } elsif ( $fld->{intype} eq RFCTYPE_FLOAT ){
        	# Float
            $value = unpack("d",$value);
          } elsif ( $fld->{intype} eq RFCTYPE_BCD and $value ){
        	#  All types of BCD
	          my @flds = split(//, unpack("H".$fld->{len1}*2, $value));
	          if ( $flds[$#flds] eq 'd' ){
	            splice( @flds,0,0,'-');
	          }
	          pop( @flds );
  	        splice(@flds,$#flds - ( $fld->{dec} - 1 ),0,'.') if $fld->{dec} > 0;
  	        $value = join('', @flds);
          } else {
	  			  # This is a char type - sort out unicode
	  				$value ||= " ";
          };
		  		$line->{$fld->{fieldname}} = $value;
		    	$cnt++;
		  }
      push(@{$self->{VALUE}}, $line);
		} else {
      push(@{$self->{VALUE}}, $row);
		}
  }
}


# Delete all rows in the table
sub empty {
  my $self = shift;
  $self->rows( [ ] );
	$self->{INTVALUE} = [ ];
  return 1;
}

# Get the table name
sub name {
  my $self = shift;
  return  $self->{NAME};
}


# Set/get the value of type
sub intype {
  my $self = shift;
  $self->{INTYPE} = shift if @_;
  #die "Table Type not valid $self->{INTYPE} !"
  #   if ! exists $TAB_VALTYPE->{$self->{INTYPE}};
  return $self->{INTYPE};
}


# Set/get the table length
sub leng {
  my $self = shift;
  $self->{LEN} = shift if @_;
  return $self->{LEN};
}


# Get the number of rows
sub rowCount {
  my $self = shift;
  return scalar @{$self->{VALUE}};
}



# Autoload methods go after =cut, and are processed by the autosplit program.


=head1 NAME

SAP::Tab - Perl extension for parsing and creating Tables to be added to an RFC Iface.

=head1 SYNOPSIS

  use SAP::Tab;
  $tab1 = new SAP::Tab( 
                INTYPE => SAP::Iface->RFCTYPE_BYTE, 
                 NAME => 'NAME_OF_TABLE',
                 STRUCTURE =>
                     $rfc->structure('NAME_OF_STRUCTURE'), 
                 LEN => 35 );


=head1 DESCRIPTION

This class is used to construct a valid Table object to be add to an interface
object ( SAP::Iface.pm ).
The constructor requires the parameter value pairs to be passed as 
hash key values ( see SYNOPSIS ).

=head1 METHODS

=head2 new()

  use SAP::Tab;
  $tab1 = new SAP::Tab(
                INTYPE => SAP::Iface->RFCTYPE_BYTE, 
                 NAME => 'NAME_OF_TABLE',
                 STRUCTURE =>
                     $rfc->structure('NAME_OF_STRUCTURE'), 
                 LEN => 35 );

=head2 rows()

  @r = $tab1->rows( [ row1, row2, row3 .... ] );
  optionally set and Give the current rows of a table.

  or:
  $tab1->rows( [ { TEXT => "NAME LIKE 'SAPL\%RFC\%'", .... } ] );
  pass in a list of hash refs where each hash ref is the key value pairs 
  of the table structures fields ( as per the DDIC ).

=head2 addRow()

  Add a row to the table contents.

=head2 hashRows()

  @r = $tab1->hashRows;
  This returns an array of hashes representing each row of a table.  
  The hashes are fieldname/value pairs of the row structure.

=head2 nextRow()

  shift the first row off the table contents, and return a hash ref of 
  the field values as per the table structure.

=head2 rowCount()

  $c = $tab1->rowCount();
  return the current number of rows in a table object.

=head2 empty()

  empty the row out of the table.

=head2 name()

  get the name of the table object.

=head2 intype()

  Set or get the internal table type.

=head2 leng()

  Set or get the table row length.

=head2 structure()

  Set or get the structure object of the table - see SAP::Struct.


=cut

package SAP::Parms;

use strict;
use vars qw($VERSION);


# Globals

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


# Valid parameters
my $PARMS_VALID = {
   RFCINTTYP => 1,
   NAME => 1,
   ENDIAN => 1,
   HANDLER => 1,
   INTYPE => 1,
   LEN => 1,
   STRUCTURE => 1,
   DECIMALS => 1,
   TYPE => 1,
   DEFAULT => 1,
   VALUE => 1,
   UNICODE => 1,
   CHANGED => 1
};


# Valid data types
my $PARMTYPE = {
   RFCEXPORT,  RFCEXPORT,
   RFCIMPORT, RFCIMPORT,
   RFCTABLE, RFCTABLE
};


# Valid data types
my $PARMS_VALTYPE = {
   RFCTYPE_CHAR, RFCTYPE_CHAR,
   RFCTYPE_BYTE, RFCTYPE_BYTE,
   RFCTYPE_BCD,  RFCTYPE_BCD,
   RFCTYPE_DATE, RFCTYPE_DATE,
   RFCTYPE_TIME,  RFCTYPE_TIME,
   RFCTYPE_NUM, RFCTYPE_NUM,
   RFCTYPE_INT, RFCTYPE_INT,
   RFCTYPE_INT2, RFCTYPE_INT2,
   RFCTYPE_INT1, RFCTYPE_INT1,
   RFCTYPE_FLOAT, RFCTYPE_FLOAT
};


# Construct a new SAP::Parms parameter object.
sub new {

  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self = {
     INTYPE => RFCTYPE_CHAR,
	   ENDIAN => join(" ", map { sprintf "%#02x", $_ } unpack("C*",pack("L",0x12345678))) eq "0x78 0x56 0x34 0x12" ? "LIT" : "BIG",
     DEFAULT => undef,
     CHANGED => 0,
     VALUE => '',
     @_
  };


  die "Parameter TYPE not supplied !" if ! exists $self->{TYPE};

  die "Parameter Type not valid $self->{TYPE} !" 
     if ! exists $PARMTYPE->{$self->{TYPE}};

#  die "Parameter Internal Type not valid $self->{INTYPE} !" 
#     if ! exists $PARMS_VALTYPE->{$self->{INTYPE}};

# Validate parameters
  map { delete $self->{$_} if ! exists $PARMS_VALID->{$_} } keys %{$self};
  $self->{NAME} = uc($self->{NAME});

# create the object and return it
  bless ($self, $class);
  return $self;
}


# Set/get the value of type
sub type {
  my $self = shift;
  $self->{TYPE} = shift if @_;
  return $self->{TYPE};
}


# get the changed flag
sub changed {
  my $self = shift;
  $self->{CHANGED} = 1 if @_;
  return $self->{'CHANGED'};
}


# Set/get the value of decimals
sub decimals {
  my $self = shift;
  $self->{DECIMALS} = shift if @_;
  return $self->{DECIMALS};
}


# Set/get the value ofinternal type
sub intype {
  my $self = shift;
  $self->{INTYPE} = shift if @_;
  return $self->{INTYPE};
}


# retrieve the rows in hashes based on the field names
sub data {
  my $self = shift;
  my @rows = ();
	my $str = $self->structure;
  foreach ( $str->fields() ){
    push ( @rows, [$str->{FIELDS}->{$_}->{INTYPE}, $str->{FIELDS}->{$_}->{OFFSET2}, $str->{FIELDS}->{$_}->{LEN2}]);
  }
  return @rows;
}

sub unicode {
  my $self = shift;
  return $self->{UNICODE};
}


# Set/get the parameter value
sub value {

  my $self = shift;

  #  there is a value
  if (@_){
    $self->{'VALUE'} = shift;
    $self->changed(1);

		# unicode and a structure
		if ($self->unicode && $self->structure){
		  # we must be given a hash
      die "in Unicode a parameter ($self->{NAME}) must be passed a HASH"
			  unless ref($self->{'VALUE'}) eq 'HASH';
     
		  # loop structure fields
			# fill in missing ones blank
			# create a hash of all for the INTVALUE
			$self->{INTVALUE} = [];
      map { 
			  my $fld = $_;
				my $value = $self->{VALUE}->{$fld->{fieldname}};
        if ( $fld->{intype} == RFCTYPE_BCD){
	        $value =~ s/^\s+([ -+]\d.*)$/$1/;
	        $value ||= 0;
	        $value = sprintf("%0".int(($fld->{len1}*2) + ($fld->{dec} > 0 ? 1:0)).".".$fld->{dec}."f", $value);
	        $value =~ s/\.//g;
	        my @flds = split(//, $value);
	        shift @flds eq '-' ? push( @flds, 'd'): push( @flds, 'c');
	        $value = join('', @flds);
          $value = pack("H*", $value);
        } elsif ( $fld->{intype} == RFCTYPE_FLOAT){
  	      $value = pack("d", $value);
        } elsif ( $fld->{intype} == RFCTYPE_INT){
  	      $value = pack(($self->{'ENDIAN'} eq "BIG" ? "l" : "V" ), int($value));
        } elsif ( $fld->{intype} == RFCTYPE_INT2){
  	      $value = pack("S", int($value));
        } elsif ( $fld->{intype} == RFCTYPE_INT1){
        # get the last byte of the integer
  				$value = chr(int($value));
        } elsif ( $fld->{intype} == RFCTYPE_DATE){
  				$value ||= '00000000';
        } elsif ( $fld->{intype} == RFCTYPE_TIME){
  				$value ||= '000000';
        } else {
				  # This is a char type - sort out unicode
					$value ||= " ";
					{
            use utf8;
            Encode::_utf8_on($value);
            if (length($value) > $fld->{len1}){
              $value = substr($value, 0, $fld->{len1});
            } else {
              $value = pack("A".$fld->{len1}, $value);
            }
            Encode::_utf8_off($value);
            no utf8;
					}
        };
				push(@{$self->{INTVALUE}}, $value);
			} ( @{$self->structure->fieldinfo} );
		}

    #  it was passed in a hash
    if (ref($self->{'VALUE'}) eq 'HASH'){
      my $str = $self->structure();
      map { $str->$_($self->{'VALUE'}->{$_}) } keys %{$self->{'VALUE'}};
      $self->{'VALUE'} = $str->value;
# don't know why I did this
#      $str->value("");
      return $self->{'VALUE'};
    } else {
      # no hash - but is a structure
      if (my $s = $self->structure ){
        $s->value( $self->{'VALUE'} ); 
        my $flds = {};
        map {  $flds->{$_} = $s->$_() } ( $s->fields );
        return $flds;
      } else {
        # no hash and no structure
	      if ($self->intype() == RFCTYPE_CHAR ||
	         $self->intype() == RFCTYPE_BYTE) {
          Encode::_utf8_off($self->{VALUE});
          if ($self->unicode){
            use utf8;
            Encode::_utf8_on($self->{VALUE});
            if (length($self->{VALUE}) > $self->leng){
              $self->{VALUE} = substr($self->{VALUE}, 0, $self->leng);
            } else {
              $self->{VALUE} = pack("A".$self->leng, $self->{VALUE});
            }
            Encode::_utf8_off($self->{VALUE});
            no utf8;
          } else {
            $self->{VALUE} = pack("A".$self->leng, $self->{VALUE});
  	      }
  	    }
      }
    }
    return $self->{'VALUE'};
  }

  # return a complex or simple parameter value
  if ($self->structure() && ! $self->unicode ){
    $self->structure->value( $self->{'VALUE'} );
    return  { map {$_ => $self->structure->$_() } ( $self->structure->fields ) };
  } else {
    return $self->{'VALUE'};
  }

}


# get the parameter internal value
sub intvalue {

  my $self = shift;

	# XXX
  ## sort out structured parameters
  #my $str = $self->structure();
  #$self->{'VALUE'} = $str->value if $str;


  # this overrides
  $self->{'VALUE'} = shift if @_;

	# sort out structured value returned from unicode call
  if (ref($self->{'VALUE'}) eq 'ARRAY' && $self->unicode){
		my $cnt = 0;

		# just put it into a hash now
		$self->{INVALUE} = [];
	  map { push(@{$self->{'INTVALUE'}}, substr($self->{'VALUE'}->[$_->{pos} -1], 0, $_->{len1})) } (@{$self->structure->fieldinfo});

    $self->{VALUE} = {};
	  foreach my $fld (@{$self->structure->fieldinfo}){
				my $value = $self->{INTVALUE}->[$cnt];
	      #  Transform various packed dta types
        if ( $fld->{intype} eq RFCTYPE_INT ){
      	# Long INT4
          $value = unpack((($self->{'RFCINTTYP'} eq 'BIG')  ? "N" : "V"), $value);
        } elsif ( $fld->{intype} eq RFCTYPE_INT2 ){
      	# Short INT2
          $value = unpack("S",$value);
        } elsif ( $fld->{intype} eq RFCTYPE_INT1 ){
      	# INT1
          $value = ord( $value );
        } elsif ( $fld->{intype} eq RFCTYPE_NUM ){
      	# NUMC
          $value = int($value);
        } elsif ( $fld->{intype} eq RFCTYPE_FLOAT ){
      	# Float
          $value = unpack("d",$value);
        } elsif ( $fld->{intype} eq RFCTYPE_BCD and $value ){
      	#  All types of BCD
	        my @flds = split(//, unpack("H".$fld->{len1}*2, $value));
	        if ( $flds[$#flds] eq 'd' ){
	          splice( @flds,0,0,'-');
	        }
	        pop( @flds );
	        splice(@flds,$#flds - ( $fld->{dec} - 1 ),0,'.') if $fld->{dec} > 0;
	        $value = join('', @flds);
        } else {
				  # This is a char type - sort out unicode
					$value ||= " ";
        };
				$self->{VALUE}->{$fld->{fieldname}} = $value;
			  $cnt++;
		}
	}


# Sort out theinternal format
  if ( defined $self->{'VALUE'} && $self->{'VALUE'} ne ''){
      if ( $self->intype() == RFCTYPE_BCD){
	      $self->{VALUE} =~ s/^\s+([ -+]\d.*)$/$1/;
	      $self->{VALUE} ||= 0;
	      my $value = sprintf("%0".int(($self->{LEN}*2) + ($self->{DECIMALS} > 0 ? 1:0)).".".$self->{DECIMALS}."f", $self->{VALUE});
	      $value =~ s/\.//g;
	      my @flds = split(//, $value);
	      shift @flds eq '-' ? push( @flds, 'd'): push( @flds, 'c');
	      $value = join('', @flds);
        return pack("H*", $value);
      } elsif ( $self->intype() == RFCTYPE_FLOAT){
	      return pack("d", $self->{VALUE});
      } elsif ( $self->intype() == RFCTYPE_INT){
	      return pack(($self->{'ENDIAN'} eq "BIG" ? "l" : "V" ), int($self->{VALUE}));
      } elsif ( $self->intype() == RFCTYPE_INT2){
	      return pack("S", int($self->{VALUE}));
      } elsif ( $self->intype() == RFCTYPE_INT1){
      # get the last byte of the integer
	      #return (unpack("A A A A", int($self->{VALUE})))[-1];
				return chr(int($self->{VALUE}));
      } else {
        if ($self->unicode){
          return $self->structure ? $self->{INTVALUE} : $self->{VALUE};
        } else {
	        return pack("A".$self->leng(),$self->{VALUE});
        }
      };
  } else {
      if ( $self->intype() == RFCTYPE_CHAR ){
        return " ";
      } else {
        return "";
      };
  };

}


# Set/get the parameter default
sub default {
  my $self = shift;
  $self->{DEFAULT} = shift if @_;
  return $self->{DEFAULT};
}


# Set/get the parameter structure
sub structure {
  my $self = shift;
  $self->{STRUCTURE} = shift if @_;
  return $self->{STRUCTURE};
}


# Set/get the parameter length
sub leng {
  my $self = shift;
  if ( $self->intype() == RFCTYPE_FLOAT){
      $self->{LEN} = 8;
  } elsif ( $self->intype() == RFCTYPE_INT){
      $self->{LEN} = 4;
  } elsif ( $self->intype() == RFCTYPE_INT2){
      $self->{LEN} = 2;
  } elsif ( $self->intype() == RFCTYPE_INT1){
      $self->{LEN} = 1;
  } else {
      $self->{LEN} = shift if @_;
  };
  return $self->{LEN};
}


# get the name
sub name {
  my $self = shift;
  return $self->{NAME};
}



=head1 NAME

SAP::Parms - Perl extension for parsing and creating an SAP parameter to be added to an RFC Interface.

=head1 SYNOPSIS

  use SAP::Parms;
  $imp1 = new SAP::Parms(
                 TYPE => SAP::Iface->RFCEXPORT,
                 INTYPE => SAP::Iface->RFCTYPE_CHAR,
                 NAME => 'A_NAME', 
                 STRUCTURE =>
                    $rfc->structure('NAME_OF_STRUCTURE'), 
                 DEFAULT => 'the default value',
                 VALUE => 'the current value',
                 DECIMALS => 0,
                 LEN => 20 );


=head1 DESCRIPTION

This class is used to construct a valid parameter to add to an interface
object ( SAP::Iface.pm ).
The constructor requires the parameter value pairs to be passed as 
hash key values ( see SYNOPSIS ).

=head1 METHODS

=head2 new()

  use SAP::Parms;
  $imp1 = new SAP::Parms(
                 TYPE => SAP::Iface->RFCEXPORT,
                 INTYPE => SAP::Iface->RFCTYPE_CHAR,
                 NAME => 'A_NAME', 
                 STRUCTURE =>
                    $rfc->structure('NAME_OF_STRUCTURE'), 
                 DEFAULT => 'the default value',
                 VALUE => 'the current value',
                 DECIMALS => 0,
                 LEN => 20 );

=head2 value()

  $v = $imp1->value( [ val ] );
  optionally set and Give the current value.

  or - pass in a hash ref where the hash ref contains  key/value pairs
  for the fields in the complex parameters structure ( as per the DDIC ).

=head2 type()

  $t = $imp1->type( [ type ] );
  optionally set and Give the current value of type - this denotes 
  whether this is an export or import parameter.

=head2 decimals()

  Set or get the decimals place of the parameter.

=head2 intype()

  Set or get the internal type ( as required by librfc ).

=head2 intvalue()

  An internal method for translating the value of a parameter into 
  the required native C format.

=head2 default()

    Set or get the place holder for the default value of a paramter 
    - in order to reset the value of a parameter to the default you 
    need to $p->value( $p->default );
    This is really an internal method that $iface->reset calls on 
    each parameter.

=head2 structure()

  Set or get the structure object for a parameter - not all 
  parameters will have an associated structures - only complex 
  ones.  See SAP::Struc.

=head2 leng()

  Set or get the length attribute of a parameter.

=head2 name()

  Get the name of a parameter object.


=cut


package SAP::Struc;

use strict;
use vars qw($VERSION $AUTOLOAD);


#  require AutoLoader;

# Globals

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


# Valid parameters
my $VALID = {
   RFCINTTYP => 1,
   LINTTYP => 1,
   NAME => 1,
   FIELDS => 1,
   TYPE => 1,
   LEN => 1,
   DATA => 1
};

# Valid Field parameters
my $FIELDVALID = {
   NAME => 1,
   ENDIAN => 1,
   INTYPE => 1,
   EXID => 1,
   DECIMALS => 1,
   LEN => 1,
   OFFSET => 1,
   LEN2 => 1,
   OFFSET2 => 1,
   LEN4 => 1,
   OFFSET4 => 1,
   POSITION => 1,
   VALUE => 1
};


# Valid data types for fields
my $VALCHARTYPE = {
   C => RFCTYPE_CHAR,

   # these shouldnt be here ...
   L => RFCTYPE_CHAR,
   G => RFCTYPE_CHAR,
   Y => RFCTYPE_CHAR,


   X => RFCTYPE_BYTE,
   B => RFCTYPE_INT1,  # This is a place holder for a 1 byte int <=255+
   S => RFCTYPE_INT2,
   P => RFCTYPE_BCD,
   D => RFCTYPE_DATE,
   T => RFCTYPE_TIME,
   N => RFCTYPE_NUM,
   F => RFCTYPE_FLOAT,
   I => RFCTYPE_INT
};


# Valid data types
my $VALTYPE = {
   RFCTYPE_CHAR, RFCTYPE_CHAR,
   RFCTYPE_BYTE, RFCTYPE_BYTE,
   RFCTYPE_BCD,  RFCTYPE_BCD,
   RFCTYPE_DATE, RFCTYPE_DATE,
   RFCTYPE_TIME,  RFCTYPE_TIME,
   RFCTYPE_NUM, RFCTYPE_NUM,
   RFCTYPE_INT, RFCTYPE_INT,
   RFCTYPE_INT1, RFCTYPE_INT1,
   RFCTYPE_INT2, RFCTYPE_INT2,
   RFCTYPE_FLOAT, RFCTYPE_FLOAT
};


# empty destroy method to stop capture by autoload
sub DESTROY {
}

sub AUTOLOAD {

  my $self = shift;
  my @parms = @_;
  my $type = ref($self)
          or die "$self is not an Object in autoload of Structure";
  my $name = $AUTOLOAD;
  $name =~ s/.*://;
  unless ( exists $self->{FIELDS}->{uc($name)} ) {
      die "Field $name does not exist in structure - no autoload";
  };
  &fieldValue($self,$name,@parms);
}

# Construct a new SAP::export parameter object.
sub new {

  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self = {
	   ENDIAN => join(" ", map { sprintf "%#02x", $_ } unpack("C*",pack("L",0x12345678))) eq "0x78 0x56 0x34 0x12" ? "LIT" : "BIG",
     FIELDS => {},
		 DATA => [],
		 LEN => 0,
		 TYPE => RFCTYPE_CHAR,
     @_
  };

  die "Structure Name not supplied !" if ! exists $self->{NAME};
  $self->{NAME} = uc($self->{NAME});

# Validate parameters
  map { delete $self->{$_} if ! exists $VALID->{$_} } keys %{$self};

# create the object and return it
  bless ($self, $class);
  return $self;

}


# Set/get structure field
sub addField {

  my $self = shift;

  my %field = @_;
  map { delete $field{$_} if ! exists $FIELDVALID->{$_} } keys %field;
  die "Structure NAME not supplied!" if ! exists $field{NAME};
  $field{NAME} = uc($field{NAME});
  $field{NAME} =~ s/\s//g;
  die "Structure NAME allready exists - $field{NAME}!" 
     if exists $self->{FIELDS}->{$field{NAME}};
  $field{INTYPE} =~ s/\s//g;
  $field{INTYPE} = uc( $field{INTYPE} );

  die "Structure INTYPE not supplied!" if ! exists $field{INTYPE};
  if ( $field{INTYPE} =~ /[A-Z]/ ){
      die "Structure Type not valid $field{INTYPE} !" 
	      if ! exists $VALCHARTYPE->{$field{INTYPE}};
      $field{INTYPE} = $VALCHARTYPE->{$field{INTYPE}};
  } else {
      die "Structure Type not valid $field{INTYPE} in $self->{NAME} - $field{NAME} - length $field{LEN} !" 
	      if ! exists $VALTYPE->{$field{INTYPE}};
  };
  $field{POSITION} = ( scalar keys %{$self->{FIELDS}} ) + 1;

  return $self->{FIELDS}->{$field{NAME}} = 
                    { map { $_ => $field{$_} } keys %field };

}


# Delete a field from the structure
sub deleteField {
  my $self = shift;
  my $field = shift;
  die "Structure field does not exist: $field "
     if ! exists $self->{FIELDS}->{uc($field)};
  delete $self->{FIELDS}->{uc($field)};
  return $field;
}


# Set/get the field value and update the overall structure value
sub fieldValue {
  my $self = shift;
  my $field = shift;
  $field = ($self->fields)[$field] if $field =~ /^\d+$/;
  die "Structure field does not exist: $field "
     if ! exists $self->{FIELDS}->{uc($field)};
  $field = $self->{FIELDS}->{uc($field)};
  if (scalar @_ > 0){
    $field->{VALUE} = shift @_;
    delete $self->{PACKED} if exists $self->{PACKED};
  } 

  return $field->{VALUE};
}


# get the field name by position
sub fieldName {
  my $self = shift;
  my $field = shift;
  die "Structure field does not exist by array position: $field "
     if ! ($self->fields)[$field - 1];
  return ($self->fields)[$field - 1 ];
}


# get the name
sub name {
  my $self = shift;
  return $self->{NAME};
}


# get the length
sub StrType {
  my $self = shift;
#	print STDERR "setting structure type : ", @_, "\n";
	$self->{'TYPE'} = shift @_ if @_;
#	print STDERR "setting Type is now: $self->{TYPE}\n";
  return $self->{'TYPE'};
}


# get the length
sub StrLength {
  my $self = shift;
  return $self->{'LEN'};
}


# return the current set of field names
sub fields {
  my $self = shift;
  return  sort { $self->{FIELDS}->{$a}->{POSITION} <=>
		  $self->{FIELDS}->{$b}->{POSITION} }
		  keys %{$self->{FIELDS}};
}


# return the current set of field names
sub fieldinfo {
  my $self = shift;
	my @data = ();
  map { push(@data, {
	                    'fieldname' => $_,
	                    'exid' => $self->{FIELDS}->{$_}->{EXID},
	                    'intype' => $self->{FIELDS}->{$_}->{INTYPE},
	                    'pos'  => $self->{FIELDS}->{$_}->{POSITION},
	                    'dec'  => $self->{FIELDS}->{$_}->{DECIMALS},
	                    'off1' => $self->{FIELDS}->{$_}->{OFFSET},
	                    'len1' => $self->{FIELDS}->{$_}->{LEN},
	                    'off2' => $self->{FIELDS}->{$_}->{OFFSET2},
	                    'len2' => $self->{FIELDS}->{$_}->{LEN2},
	                    'off4' => $self->{FIELDS}->{$_}->{OFFSET4},
	                    'len4' => $self->{FIELDS}->{$_}->{LEN4}
	                   })
	      }
	    sort { $self->{FIELDS}->{$a}->{POSITION} <=>
		  $self->{FIELDS}->{$b}->{POSITION} }
		  keys %{$self->{FIELDS}};
	return \@data;
}


# Set/get the parameter value
sub value {
  my $self = shift;
  # an empty value maybe passed
  if ( scalar @_ > 0 ){
    $self->{VALUE} = shift @_ ;
    _unpack_structure( $self );
  } else {
    _pack_structure( $self ) if ! exists $self->{PACKED};
  }
  return $self->{VALUE};
}


sub hash {
  my $self = shift;
  return  { map {$_ => $self->$_() } ( $self->fields ) };
}


# internal routine to pack individual field values back into structure
sub _pack_structure {

  my $self = shift;
  my @fields = fields($self);
  my $offset = 0;
  my @flds = undef;
  map {
        my $fld = $self->{FIELDS}->{$fields[$_]};
        $fld->{OFFSET} = $offset if ! $fld->{OFFSET} > 0;
        $offset += int($fld->{LEN});
	#  Transform various packed dta types
        if ( $fld->{INTYPE} eq RFCTYPE_INT ){
	# Long INT4
      	  $fld->{VALUE} ||= 0;
	  $fld->{VALUE} = pack(($self->{'RFCINTTYP'} eq 'BIG' ? "N" : "V"), int($fld->{VALUE}));
        } elsif ( $fld->{INTYPE} eq RFCTYPE_INT2 ){
	# Short INT2
	        $fld->{VALUE} ||= 0;
          $fld->{VALUE} = pack("S",$fld->{VALUE});
        } elsif ( $fld->{INTYPE} eq RFCTYPE_INT1 ){
	# Short INT1
          $fld->{VALUE} = chr( int( $fld->{VALUE} ) );
        } elsif ( $fld->{INTYPE} eq RFCTYPE_NUM ){
	# NUMC
# what if it is num char ?
          $fld->{VALUE} = "0" unless exists $fld->{VALUE};
	        if ( $fld->{VALUE} == 0 || $fld->{VALUE} =~ /^[0-9]+$/ ){
	          $fld->{VALUE} = 
	            sprintf("%0".$fld->{LEN}."d", int($fld->{VALUE}));
	        };
        } elsif ( $fld->{INTYPE} eq RFCTYPE_DATE ){
	# Date
          $fld->{VALUE} = '00000000' if ! $fld->{VALUE};
        } elsif ( $fld->{INTYPE} eq RFCTYPE_TIME ){
	# Time
          $fld->{VALUE} = '000000' if ! $fld->{VALUE};
        } elsif ( $fld->{INTYPE} eq RFCTYPE_FLOAT ){
	# Float
	        $fld->{VALUE} ||= 0;
          $fld->{VALUE} = pack("d",$fld->{VALUE});
        } elsif ( $fld->{INTYPE} eq RFCTYPE_BCD ){
	#  All types of BCD
	        $fld->{VALUE} =~ s/^\s+([ -+]\d.*)$/$1/;
	        $fld->{VALUE} ||= 0;
#	        $fld->{VALUE} = sprintf("%0".int(($fld->{LEN}*2) + ($fld->{DECIMALS} > 1 ? 1:0)).".".$fld->{DECIMALS}."f", $fld->{VALUE});
	        $fld->{VALUE} = sprintf("%0".int(($fld->{LEN}*2) + ($fld->{DECIMALS} > 0 ? 1:0)).".".$fld->{DECIMALS}."f", $fld->{VALUE});
	        #warn "MASK: %0".int(($fld->{LEN}*2) + ($fld->{DECIMALS} > 1 ? 1:0)).".".$fld->{DECIMALS}."f\n";
	        $fld->{VALUE} =~ s/\.//g;
	        @flds = split(//, $fld->{VALUE});
	        shift @flds eq '-' ? push( @flds, 'd'): push( @flds, 'c');
	        $fld->{VALUE} = join('', @flds);
          #warn "$fld->{NAME}: $fld->{LEN}/$fld->{DECIMALS} - $fld->{VALUE} lval:".length($fld->{VALUE})."\n";
          $fld->{VALUE} = pack("H*",$fld->{VALUE});
        }
	      $fld->{VALUE} ||= "";
      } (0..$#fields);

  # find the length of a row
  my $lastoff = $self->{FIELDS}->{$fields[$#fields]}->{OFFSET} + 
                $self->{FIELDS}->{$fields[$#fields]}->{LEN};
  my $format = "";
  map {
        my $fld = $self->{FIELDS}->{$fields[$_]};
	      $format = join(" ","A".($lastoff - $fld->{OFFSET}), $format);
        $lastoff = int($fld->{OFFSET});
      } reverse (0..$#fields);

  $self->{VALUE} = 
    pack( $format, ( map { $self->{FIELDS}->{$_}->{VALUE} } ( @fields ) ) );
  $self->{PACKED} = 1;

}


# internal routine to unpack field values from the overall structure value
sub _unpack_structure {

  my $self = shift;
  my @fields = $self->fields($self);
	#print STDERR "unpacking: $self->{NAME} => $self->{VALUE} \n";
	#use Data::Dumper;
	#print STDERR Dumper($self->{DATA})."\n";
  my $offset = 0;
  map {
        my $fld = $self->{FIELDS}->{$fields[$_]};
        $offset = int($fld->{OFFSET}) if exists $fld->{OFFSET};
#				print STDERR "field: $fld->{NAME} type: $fld->{INTYPE} len: $fld->{LEN} off: $offset\n";
        $fld->{VALUE} = substr($self->{VALUE}, $offset, int($fld->{LEN}));
#				print STDERR "actual length: ".length($self->{VALUE})."\n";
#				print STDERR "field value: ".unpack("H*", $fld->{VALUE})."#\n";
	#  Transform various packed dta types
        if ( $fld->{INTYPE} eq RFCTYPE_INT ){
	# Long INT4
          $fld->{VALUE} = 
	     unpack((($self->{'RFCINTTYP'} eq 'BIG')  ? "N" : "V"), $fld->{VALUE});
        } elsif ( $fld->{INTYPE} eq RFCTYPE_INT2 ){
	# Short INT2
#	        print STDERR "extracting $fld->{NAME} => ".unpack("H*", $fld->{VALUE})."\n";
          $fld->{VALUE} = unpack("S",$fld->{VALUE});
        } elsif ( $fld->{INTYPE} eq RFCTYPE_INT1 ){
	# INT1
          $fld->{VALUE} = ord( $fld->{VALUE} );
        } elsif ( $fld->{INTYPE} eq RFCTYPE_NUM ){
	# NUMC
          $fld->{VALUE} = int($fld->{VALUE});
        } elsif ( $fld->{INTYPE} eq RFCTYPE_FLOAT ){
	# Float
          $fld->{VALUE} = unpack("d",$fld->{VALUE});
        } elsif ( $fld->{INTYPE} eq RFCTYPE_BCD and $fld->{VALUE} ){
	#  All types of BCD
	        my @flds = split(//, unpack("H".$fld->{LEN}*2,$fld->{VALUE}));
	        if ( $flds[$#flds] eq 'd' ){
	          splice( @flds,0,0,'-');
	        }
	        pop( @flds );
	        splice(@flds,$#flds - ( $fld->{DECIMALS} - 1 ),0,'.')
	                if $fld->{DECIMALS} > 0;
	        $fld->{VALUE} = join('', @flds);
       }
        $offset += int($fld->{LEN}) if ! exists $fld->{OFFSET};
     } (0..$#fields);

}



=head1 NAME

SAP::Struc - Perl extension for parsing and creating a Structure definition.   The resulting structure object is then used for SAP::Parms, and SAP::Tab objects to manipulate complex data elements.

=head1 SYNOPSIS

  use SAP::Struc;
  $struct = new SAP::Struc( NAME => XYZ, FIELDS => [......] );

=head1 DESCRIPTION

This class is used to construct a valid structure object - a structure object that would be used in an Export(Parms), Import(Parms), and Table(Tab) object ( SAP::Iface.pm ).  This is normally done through the SAP::Rfc->structure('STRUCT_NAME') method that does an auto look up of the data dictionary definition of a structure.
The constructor requires the parameter value pairs to be passed as 
hash key values ( see SYNOPSIS ).  The value of each field can either be accessed through $str->fieldValue(field1), or through the autoloaded method of the field name eg. $str->FIELD1().  

=head1 METHODS

=head2 new()

  use SAP::Struc;
  $str = new SAP::Struc( NAME => XYZ );


=head2 addField()

  use SAP::Struc;
  $str = new SAP::Struc( NAME => XYZ );
  $str->addField( NAME => field1,
                  INTYPE => chars );
  add a new field into the structure object.  The field is given a 
  position counter of the number of the previous number of fields + 1.
  Name is mandatory, but type will be defaulted to chars if omitted.


=head2 deleteField()

  use SAP::Struc;
  $str = new SAP::Struc( NAME => XYZ );
  $str->addField( NAME => field1,
                  INTYPE => chars );
  $str->deleteField('field1');
  Allow fields to be deleted from a structure.


=head2 name()

  $name = $str->name();
  Get the name of the structure.


=head2 fieldName()

  Get the field name by position in the structure - $s->fieldName( 3 ).


=head2 fieldType()

  $ftype = $str->fieldType(field1, [ new field type ]);
  Set/Get the SAP BC field type of a component field of the structure.
  This will force the overall value of the structure to be recalculated.


=head2 value()

  $fvalue = $str->value('new value');
  Set/Get the value of the whole structure.


=head2 hash()

  $val = $str->hash();
  Get a hash of the values of the whole structure (current value).


=head2 fieldValue()

  $fvalue = $str->fieldValue(field1,
                          [new component value]);
  Set/Get the value of a component field of the structure.  This will 
  force the overall value of the structure to be recalculated.


=head2 fields()

  @f = $struct->fields();
  Return an array of the fields of a structure sorted in positional
  order.


=head1 Exported constants

  NONE


=head1 AUTHOR

Piers Harding, saprfc@ompa.net

But Credit must go to all those that have helped.

=head1 SEE ALSO

perl(1), SAP(3), SAP::Rfc(3), SAP::Iface(3)

=cut


1;
