#!/usr/bin/perl
use lib '../lib';
use SAP::Rfc;
use Data::Dumper;

$|++;
#   get a list of report names from table TRDIR and 
#   then get the source code of each


my $rfc = new SAP::Rfc(
              ASHOST   => 'kogut',
              USER     => 'DEVELOPER',
              PASSWD   => 'secret',
              LANG     => 'EN',
              CLIENT   => '000',
		       SYSNR    => '17');
#              TRACE    => '1' );

my $it = $rfc->discover("RFC_READ_TABLE");

$it->QUERY_TABLE('TRDIR');
$it->DELIMITER('|');
$it->ROWCOUNT( 5 );
$it->OPTIONS( ["NAME LIKE 'RS%'"] );

$rfc->callrfc( $it );
print "SOAP REQUEST AFTER: ".$it->soapResponse();

my $if = $rfc->discover("RFC_READ_REPORT");
$if->PROGRAM('SAPLGRAP');
$rfc->callrfc( $if );
print "DONE CALL \n";

print "SOAP REQUEST AFTER: ".$if->soapResponse();

$rfc->close();








