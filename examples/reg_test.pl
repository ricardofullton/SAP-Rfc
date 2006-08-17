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

my $rfc1 = new SAP::Rfc(
              ASHOST   => 'seahorse.local.net',
              SYSNR   => '00',
              LANG   => 'EN',
              CLIENT   => '010',
              USER   => 'developer',
              PASSWD   => 'developer',
              TRACE    => '1' );
my $ztable = $rfc1->structure("ZTABLE");
$rfc1->close();

my $rfc = new SAP::Rfc(
              TPNAME   => 'wibble.rfcexec',
              GWHOST   => 'seahorse.local.net',
              GWSERV   => '3300',
              TRACE    => '1' );

my $iface = new SAP::Iface(NAME => "DATATEST", HANDLER => \&do_remote_pipe, UNICODE => $rfc->unicode);
$iface->addParm( TYPE => $iface->RFCIMPORT, INTYPE => $iface->RFCTYPE_CHAR, NAME => "COMMAND", LEN => 256);
$iface->addParm( TYPE => $iface->RFCEXPORT, INTYPE => $iface->RFCTYPE_CHAR, NAME => "ECOMMAND", LEN => 256);
$iface->addParm( TYPE => $iface->RFCIMPORT, INTYPE => $iface->RFCTYPE_CHAR, NAME => "READ", LEN => 1);
$iface->addParm( TYPE => $iface->RFCIMPORT, INTYPE => $iface->RFCTYPE_DATE, NAME => "DATE", LEN => 8);
$iface->addParm( TYPE => $iface->RFCEXPORT, INTYPE => $iface->RFCTYPE_DATE, NAME => "EDATE", LEN => 8);
$iface->addParm( TYPE => $iface->RFCIMPORT, INTYPE => $iface->RFCTYPE_TIME, NAME => "TIME", LEN => 6);
$iface->addParm( TYPE => $iface->RFCEXPORT, INTYPE => $iface->RFCTYPE_TIME, NAME => "ETIME", LEN => 6);
$iface->addParm( TYPE => $iface->RFCIMPORT, INTYPE => $iface->RFCTYPE_INT, NAME => "INT4", LEN => 4);
$iface->addParm( TYPE => $iface->RFCEXPORT, INTYPE => $iface->RFCTYPE_INT, NAME => "EINT4", LEN => 4);
$iface->addParm( TYPE => $iface->RFCIMPORT, INTYPE => $iface->RFCTYPE_INT1, NAME => "INT1", LEN => 1);
$iface->addParm( TYPE => $iface->RFCEXPORT, INTYPE => $iface->RFCTYPE_INT1, NAME => "EINT1", LEN => 1);
$iface->addParm( TYPE => $iface->RFCIMPORT, INTYPE => $iface->RFCTYPE_INT2, NAME => "INT2", LEN => 2);
$iface->addParm( TYPE => $iface->RFCEXPORT, INTYPE => $iface->RFCTYPE_INT2, NAME => "EINT2", LEN => 2);
$iface->addParm( TYPE => $iface->RFCIMPORT, INTYPE => $iface->RFCTYPE_FLOAT, NAME => "FLT", LEN => 8);
$iface->addParm( TYPE => $iface->RFCEXPORT, INTYPE => $iface->RFCTYPE_FLOAT, NAME => "EFLT", LEN => 8);
$iface->addParm( TYPE => $iface->RFCIMPORT, INTYPE => $ztable->StrType, NAME => "ISTRUCT", LEN => $ztable->StrLength, STRUCTURE => $ztable);
$iface->addParm( TYPE => $iface->RFCEXPORT, INTYPE => $ztable->StrType, NAME => "ESTRUCT", LEN => $ztable->StrLength, STRUCTURE => $ztable);
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

sub do_remote_pipe {
  my $iface = shift;
  warn "Running do_remote_pipe...\n";
  my $ls = $iface->COMMAND;
  $iface->PIPEDATA( [ map { pack("A80",$_) } split(/\n/, `$ls`) ]);
  #die "MY_CUSTOM_ERROR with some other text";
	$iface->ecommand($iface->command);
	$iface->edate($iface->date);
	$iface->etime($iface->time);
	$iface->eint4($iface->int4);
	$iface->eint1($iface->int1);
	$iface->eint2($iface->int2);
	$iface->eflt($iface->flt);
	warn "istruct: ".Dumper($iface->istruct)."\n";
	$iface->estruct($iface->istruct);
  warn "called $$\n";
  return 1;
}


sub debug {
  return unless $DEBUG;
  print  STDERR scalar localtime().": ", @_, "\n";
}

