#!/usr/bin/perl
use SAP::Rfc;
use Data::Dumper;

#   get a list of report names from table TRDIR and 
#   then get the source code of each

#print "VERSION: ".$SAP::Rfc::VERSION ."\n";
#exit 0;


my $rfc = new SAP::Rfc(
              ASHOST   => 'localhost',
              USER     => 'DEVELOPER',
              PASSWD   => '19920706',
              LANG     => 'EN',
              CLIENT   => '000',
              SYSNR    => '18',
              TRACE    => '1' );


print " START: ".scalar localtime() ."\n";

my $it = $rfc->discover("RFC_READ_TABLE");

$it->QUERY_TABLE('TRDIR');
$it->DELIMITER('|');
$it->ROWCOUNT( 1000 );
$it->OPTIONS( ["NAME LIKE 'RS%'"] );

$rfc->callrfc( $it );

print "NO. PROGS: ".$it->tab('DATA')->rowCount()." \n";


$if =  $rfc->discover( "RFC_READ_REPORT" );

my $tot = 0;
my $c = 0;

for my $row ( $it->DATA ){

    $c++;
    my $prog = (split(/\|/,$row))[0];
    $if->reset();
    $if->PROGRAM( $prog );
    $rfc->callrfc( $if );
    # print Dumper( $if );
    my $rows =   ( $if->QTAB );
    $tot += $rows;
    print "No. $c PROGRAM: $prog   ROWS: $rows  TOTAL: $tot\n";
#    print "CODE: ".join("\n",( $if->QTAB ));
    #print Dumper( $if->TRDIR() );

}

$rfc->close();

print " END: ".scalar localtime() ."\n";
print " TOTAL ROWS: $tot \n";







