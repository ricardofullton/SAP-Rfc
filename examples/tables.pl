#!/usr/bin/perl
use strict;
use lib '../blib/lib';
use lib '../blib/arch';
use SAP::Rfc;
use Data::Dumper;

#   get a list of report names from table TRDIR and 
#   then get the source code of each

print "SAP::Rfc VERSION: $SAP::Rfc::VERSION \n";
print "SAP::Iface VERSION: $SAP::Iface::VERSION \n";


my $rfc = new SAP::Rfc(
              ASHOST   => 'seahorse',
              USER     => 'DEVELOPER',
              PASSWD   => 'developer',
              LANG     => 'EN',
              CLIENT   => '010',
              SYSNR    => '00',
              TRACE    => '1' );



my $table = 'TRDIR';

my $it = $rfc->discover("RFC_READ_TABLE");
my $s = $rfc->structure($table);

$it->QUERY_TABLE($table);
#$it->DELIMITER('|');
$it->ROWCOUNT( 10 );
warn "ROWS before: ".$it->ROWCOUNT()."\n";
$it->OPTIONS( ["NAME LIKE 'SAPL\%RFC\%'"] );

$rfc->callrfc( $it );


print "NO. PROGS: ".$it->tab('DATA')->rowCount()." \n";

exit;


for my $row ( $it->DATA ){
  $s->value( $row );
  my $hashrow =  { map { $_ => $s->$_() } ( $s->fields ) };
  print Dumper( $hashrow );

}

$rfc->close();
