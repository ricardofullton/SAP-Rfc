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
my $it = $rfc->discover("RS_UNI_INSTALLED_LANGU_GET");
$rfc->callrfc( $it );
for my $row ( $it->tab('E_T_LANGU')->hashRows ){
    print "ROW: ".Dumper($row)."\n";
}
$rfc->close();

print " END: ".scalar localtime() ."\n";







