#!/usr/bin/perl
use lib '../blib/lib';
use lib '../blib/arch';
use lib './blib/lib';
use lib './blib/arch';

use SAP::Rfc;
use Data::Dumper;
print "VERSION: ".$SAP::Rfc::VERSION ."\n";
my $rfc = new SAP::Rfc(
              ASHOST   => 'seahorse',
              USER     => 'developer',
              PASSWD   => 'developer',
              LANG     => 'EN',
              CLIENT   => '000',
              SYSNR    => '00',
              TRACE    => '1' );

print " START: ".scalar localtime() ."\n";
my $it = $rfc->discover("BAPI_CUSTOMER_GETDETAIL2");
$it->CUSTOMERNO('0001409010');
$rfc->callrfc( $it );
print "CUST: ".Dumper($it->CUSTOMERADDRESS())." \n";
$rfc->close();
print " END: ".scalar localtime() ."\n";







