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
#exit 0;


my $rfc = new SAP::Rfc(
              TPNAME   => 'wibble.rfcexec',
              GWHOST   => '172.22.50.1',
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

my $iface2 = new SAP::Iface(NAME => "RFC_REMOTE_PIPE", HANDLER => \&do_remote_pipe);
$iface2->addParm( TYPE => $iface->RFCIMPORT,
                 INTYPE => $iface->RFCTYPE_CHAR,
                 NAME => "COMMAND",
                 LEN => 256);
$iface2->addParm( TYPE => $iface->RFCIMPORT,
                 INTYPE => $iface->RFCTYPE_CHAR,
                 NAME => "READ",
                 LEN => 1);
$iface2->addTab( NAME => "PIPEDATA",
                LEN => 80);

$rfc->iface($iface2);


print " START: ".scalar localtime() ."\n";

$rfc->accept();


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
  warn "   Data: ".Dumper($iface->PIPEDATA);
  return 1;

}


sub debug{
  return unless $DEBUG;
    print  STDERR scalar localtime().": ", @_, "\n";
    }

