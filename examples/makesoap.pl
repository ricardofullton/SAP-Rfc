#!/usr/bin/perl
use lib '../lib';
use lib './lib';
use lib '../blib/lib';
use lib '../blib/arch';
#use SAP::Rfc;
use SAP::SOAP;
use Data::Dumper;

$|++;
#   get a list of report names from table TRDIR and 
#   then get the source code of each


my $rfc = new SAP::SOAP(
              ASHOST   => 'localhost',
              USER     => 'DEVELOPER',
              PASSWD   => '19920706',
              LANG     => 'EN',
              CLIENT   => '000',
	       SYSNR    => '18');

my $it = $rfc->discover("RFC_READ_TABLE");

$it->QUERY_TABLE('TRDIR');
$it->DELIMITER('|');
$it->ROWCOUNT( 5 );
$it->OPTIONS( ["NAME LIKE 'RS%'"] );

$rfc->callrfc( $it );
print "SOAP REQUEST AFTER: ".$rfc->soapResponse($it);

my $if = $rfc->discover("RFC_READ_REPORT");
$if->PROGRAM('SAPLGRAP');
$rfc->callrfc( $if );
print "DONE CALL \n";

print "SOAP REQUEST AFTER: ".$rfc->soapResponse($if);

$rfc->close();








