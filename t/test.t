# Need to suppress warinings ?
BEGIN { $^W = 0; $| = 1; print "1..4\n"; }
END {print "not ok 1\n" unless $loaded;}
use SAP::Rfc;
$loaded = 1;
print "ok 1\n";                                                                                     

my $rfc = new SAP::Rfc( './testconn' );

print "Testing SAP::Rfc-$SAP::Rfc::VERSION\n";
print $rfc->is_connected ? "ok 2" : "not ok 2", "\n";
print $rfc->discover('RFC_READ_REPORT') ? "ok 3" : "not ok 3", "\n";
print getSource( $rfc ) ? "ok 4" : "not ok 4", "\n";




sub getSource{

 my $rfc = shift;
 my $if = $rfc->discover('RFC_READ_REPORT');

 $if->PROGRAM('SAPLGRAP');

 $rfc->callrfc( $if );

 # Check for a particular line
 return join('', map { $_->{LINE} } $if->tab('QTAB')->hashRows() ) =~ /LGRAPUXX/;

}
