#!/usr/bin/perl

use lib '../blib/lib';
use lib '../blib/arch';
use SAP::Rfc;
use SAP::Iface;
use Data::Dumper;


use DBI qw(:sql_types);
use vars qw($DEBUG $DBH);
$DEBUG = 1;

my $config = {
       'DB' => 'mysql',
       'DBName' => 'mysql',
       'DBHost' => 'tool00.bydeluxe.net',
       'DBUser' => 'root',
       'DBPasswd' => 'mental',
       };


#   Register an external program to provide outbound
#   RFCs

print "VERSION: ".$SAP::Rfc::VERSION ."\n";
$SAP::Rfc::EXCEPTION_ONLY = 1;
print "EXCEPTION: ".$SAP::Rfc::EXCEPTION_ONLY ."\n";
#exit 0;


my $rfc = new SAP::Rfc(
              TPNAME   => 'wibble.rfcexec',
              GWHOST   => '172.22.50.1',
              #GWHOST   => '172.22.50.76',
              i#GWHOST   => 'seahorse.local.net',
              GWSERV   => '3300',
              TRACE    => '1' );

my $iface = new SAP::Iface(NAME => "RFC_DEMO", HANDLER => \&do_demo);
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
$iface->addTab( NAME => "TAB1",
                LEN => 200);

$rfc->iface($iface);

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

$rfc->iface($iface);


print " START: ".scalar localtime() ."\n";

$rfc->accept(\&do_something, 5);

warn "ERR: ".$rfc->error ."\n";

sub do_something {

  my $thing = shift;

  warn "Running do_something ...\n";
  warn "Got: $thing \n";

  #return $iface;

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
  #warn "   Data: ".Dumper($iface->PIPEDATA);
  #die "MY_CUSTOM_ERROR with some other text";
  warn "called $$\n";
  return 1;

}


sub debug{
  return unless $DEBUG;
    print  STDERR scalar localtime().": ", @_, "\n";
    }

