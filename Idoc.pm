package SAP::Idoc;

use strict;

require 5.005;

use vars qw($VERSION $AUTOLOAD);
$VERSION = '0.01';


# work arround for the VERSION IDOC Segment
sub VERSION {
  my $self = shift;
  my $name = 'VERSION';
  if ( exists $self->{'SEGMENTS'}->{uc($name)} ) {
      return &segment($self, $name);
  } else {
      die "Segment $name does not exist in IDOC - no autoload";
  };
}


sub AUTOLOAD {
  my $self = shift;
  my @parms = @_;
  my $type = ref($self)
          or die "$self is not an Object in autoload of IDOC";
  my $name = $AUTOLOAD;
  $name =~ s/.*://;

  if ( exists $self->{'SEGMENTS'}->{uc($name)} ) {
     return &segment($self, $name);
  } else {
     die "Segment $name does not exist in IDOC - no autoload";
  };
}


sub new {

    my $proto = shift;
    my $class = ref($proto) || $proto;
    
    my $self = {
	  NAME => '',
	  cnt => 1,
	  SEGMENTS => {},
      LINTTYP => ( ( join(" ", map { sprintf "%#02x", $_ } unpack("C*",pack("L",0x12345678))) eq "0x78 0x56 0x34 0x12") ? "LIT" : "BIG" ),
  	  @_,
	};

	die "must provide a name for an IDOC definition\n"
	   unless $self->{'NAME'};

# create the object and return it
    bless ($self, $class);
    return $self;
}


sub name {
  my $self = shift;
  $self->{'NAME'} = shift if @_;
  return $self->{'NAME'};
}


sub _addSegment {
  my $self = shift;
  my ($segment, $def) = @_;
  $self->{'SEGMENTS'}->{$segment->name} = 
         { 'structure' => $segment,
		   'segment' => $def }; 
}



#my $last;

#need to sort out where the segment level comes from so that it is automatically determined

# add each segment to the data table
sub addSegment {
  my $self = shift;
  my $str = shift;
  my $datastr = $self->{'SINGLE'}->tab('PT_IDOC_DATA_RECORDS_40')->structure();
  $datastr->value( undef );
  $datastr->SEGNAM( $str->name );
  $datastr->MANDT($self->{'MANDT'});
  $datastr->HLEVEL($self->{'SEGMENTS'}->{$str->name}->{'segment'}->{'HLEVEL'});
  $datastr->SEGNUM($self->{'cnt'}++);
  #if ( $datastr->HLEVEL < '03' ){
  #  $last = $datastr->SEGNUM;
  #} else {
  #  $datastr->PSGNUM($last);
  #}
  $datastr->SDATA($str->value());
  $self->{'SINGLE'}->tab('PT_IDOC_DATA_RECORDS_40')->addRow($datastr->value());
  #my $row = $datastr->value();
  #$row =~ s/^(.*?)\s*$/$1/;
  #print "DATA: ", $row, "\n";
}


sub segment {
  my $self = shift;
  my ($segment) = @_;
  return $self->{'SEGMENTS'}->{$segment}->{'structure'};
}


sub idocSingle {
  my $self = shift;
  my $ctl = $self->{'SINGLE'}->parm('PI_IDOC_CONTROL_REC_40');
  $ctl->value( $ctl->structure->value() );
  return $self->{'SINGLE'};
}

sub reset {
  my $self = shift;
  $self->{'cnt'} = 1;
  $self->{'SINGLE'}->reset;
}



=head1 NAME

SAP::Idoc - container for IDOC attributes

=head1 SYNOPSIS

  use SAP::Rfc;
  $rfc = new SAP::Rfc( ... );
  my $idoc = $rfc->lookup_idoc("USERCLONE03");
  ...


=head1 DESCRIPTION

SAP::Idoc - is a container class for the details of what is an IDOC



=head1 METHODS:

=head2 name()

  $idoc->name( <val> )

  set and/or retrieve the name of an IDOC



=head1 AUTHOR

Piers Harding, piers@ompa.net.

But Credit must go to all those that have helped.


=head1 SEE ALSO

perl(1), SAP::Rfc(3), SAP::Iface(3).

=cut


1;
