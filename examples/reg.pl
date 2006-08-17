#!/usr/bin/perl
use lib '../blib/lib';
use lib '../blib/arch';
use lib './blib/lib';
use lib './blib/arch';
use SAP::Rfc;
use SAP::Iface;
use Data::Dumper;


#   Register an external program to provide outbound
#   RFCs

print "VERSION: ".$SAP::Rfc::VERSION ."\n";
$SAP::Rfc::EXCEPTION_ONLY = 1;
print "EXCEPTION: ".$SAP::Rfc::EXCEPTION_ONLY ."\n";


my $rfc = new SAP::Rfc(
              TPNAME   => 'wibble.rfcexec',
              GWHOST   => 'seahorse.local.net',
              GWSERV   => '3300',
              TRACE    => '1' );

my $iface = new SAP::Iface(NAME => "RFC_DEMO", HANDLER => \&do_demo, UNICODE => $rfc->unicode);
$iface->addParm( TYPE => $iface->RFCEXPORT,
                 INTYPE => $iface->RFCTYPE_CHAR,
                 NAME => "EXP1",
                 LEN => 75);
$iface->addParm( TYPE => $iface->RFCEXPORT,
                 INTYPE => $iface->RFCTYPE_CHAR,
                 NAME => "EXP2",
                 LEN => 3);
$iface->addParm( TYPE => $iface->RFCIMPORT,
                 INTYPE => $iface->RFCTYPE_CHAR,
                 NAME => "IMP1",
                 LEN => 1);
my $tab1str = SAP::Struc->new( NAME => "TAB1STRUCT");
$tab1str->addField(
         NAME     => "LINE",
         LEN      => 200,
         OFFSET   => 0,
         DECIMALS => 0,
         EXID     => "C",
         INTYPE   => "C",
         LEN2     => 400,
         OFFSET2  => 0,
         LEN4     => 800,
         OFFSET4  => 0,
			  );
$iface->addTab( NAME => "TAB1",
                LEN => 200,
                INTYPE => RFCTYPE_CHAR,
								STRUCTURE => $tab1str );
$rfc->iface($iface);

my $iface = new SAP::Iface(NAME => "RFC_REMOTE_PIPE", HANDLER => \&do_remote_pipe, UNICODE => $rfc->unicode);
$iface->addParm( TYPE => $iface->RFCIMPORT,
                 INTYPE => $iface->RFCTYPE_CHAR,
                 NAME => "COMMAND",
                 LEN => 256);
$iface->addParm( TYPE => $iface->RFCIMPORT,
                 INTYPE => $iface->RFCTYPE_CHAR,
                 NAME => "READ",
                 LEN => 1);
my $pipestr = SAP::Struc->new( NAME => "PIPERESULT");
$pipestr->addField(
         NAME     => "LINE",
         LEN      => 80,
         OFFSET   => 0,
         DECIMALS => 0,
         EXID     => "C",
         INTYPE   => "C",
         LEN2     => 160,
         OFFSET2  => 0,
         LEN4     => 320,
         OFFSET4  => 0,
			  );
$iface->addTab( NAME => "PIPEDATA",
                LEN => $rfc->unicode ? 160 : 80,
                INTYPE => RFCTYPE_CHAR,
								STRUCTURE => $pipestr);

$rfc->iface($iface);

print " START: ".scalar localtime() ."\n";

$rfc->accept(\&do_something, 5);

warn "ERR: ".$rfc->error ."\n";

sub do_something {
  my $thing = shift;
  warn "Running do_something ...\n";
  warn "Got: $thing \n";
}


sub do_demo {
  my $iface = shift;
  warn "Running do_demo...\n";
  return $iface;
}

sub do_remote_pipe {
  my $iface = shift;
  warn "Running do_remote_pipe...\n";
  my $ls = $iface->COMMAND;
  $iface->PIPEDATA( [ map { pack("A80",$_) } split(/\n/, `$ls`) ]);
  #die "MY_CUSTOM_ERROR with some other text";
  warn "called $$\n";
  return 1;
}


sub debug {
  return unless $DEBUG;
  print  STDERR scalar localtime().": ", @_, "\n";
}

