# Need to suppress warinings ?
BEGIN { $^W = 0; $| = 1; print "1..6\n"; }
END {print "not ok 1\n" unless $loaded;}
use SAP::Rfc;
$loaded = 1;
print "ok 1\n";                                                                                     

my $rfc = new SAP::Rfc( './testconn' );

print "Testing SAP::Rfc-$SAP::Rfc::VERSION\n";
print $rfc->is_connected ? "ok 2" : "not ok 2", "\n";
print $rfc->discover('RFC_READ_REPORT') ? "ok 3" : "not ok 3", "\n";
print getSource( $rfc ) ? "ok 4" : "not ok 4", "\n";
print getTable( $rfc ) ? "ok 5" : "not ok 5", "\n";
print getError( $rfc ) ? "ok 6" : "not ok 6", "\n";




sub getSource{

 my $rfc = shift;
 use Data::Dumper;
 #my $if = $rfc->discover('RFC_READ_REPORT'); # code commented out
 my $if = $rfc->discover('RFC_READ_DEVELOPMENT_OBJECT'); 
 $if->PROGRAM('SAPLGRFC');
 $rfc->callrfc( $if );
# print STDERR Dumper($if);

 # Check for a particular line
 #print STDERR "SOURCE: ".join("\n",Dumper($if->tab('QTAB')->rows()));
 return join('', map { $_->{LINE} } $if->tab('QTAB')->hashRows() ) =~ /LGRFCUXX/s;

}


sub getError {

 my $rfc = shift;
 use Data::Dumper;
 my $if = $rfc->discover('RFC_READ_REPORT');
 # break the interface definition
 $if->{'NAME'} = 'WIBBLE';
 $if->PROGRAM('SAPLGRFC');
 eval { $rfc->callrfc( $if ); };
 #warn "the Error is: ".$rfc->error."\n";
 return $rfc->error() =~ /WIBBLE/s ? 1 : 0;

}


sub getTable {

 my $rfc = shift;
 my $cnt = 0;
 my $if = $rfc->discover("RFC_READ_TABLE");
 $if->QUERY_TABLE('T000');
 my $flds = $if->tab('FIELDS')->structure();
 $if->FIELDS([{ 'FIELDNAME' => "MANDT"}, { 'FIELDNAME' => "MTEXT"}, { 'FIELDNAME' => "ORT01"}]);
 my $str = $rfc->structure('T000');
 $rfc->callrfc($if);
 foreach my $row ($if->DATA()){
   #warn Dumper($row)."\n";
	 if ($if->unicode){
     $str->value($row->{'WA'});
	 } else {
     $str->value($row);
	 }
   $cnt += 1 if $str->MANDT eq '066';
 }
 $if->reset;
# $if->QUERY_TABLE('TNRO');
# $if->DELIMITER('|');
# my $flds = $if->tab('FIELDS')->structure();
# $if->OPTIONS( [ {'TEXT' => "OBJECT LIKE 'ARCHIVELNK%'"}] );
# #my $str = $rfc->structure('TNRO');
# $rfc->callrfc($if);
# foreach my $row ($if->DATA()){
##   $str->value($row);
##   return 1 if $str->MANDT eq '066';
#   warn "row: ".$row."\n";
# }
# foreach my $row ($if->DATA()){
#   $str->value($row);
#   $cnt +=1 if $str->OBJECT =~ /ARCHIVE/;
#   #warn "TNRO: ".$str->OBJECT." ".$str->PERCENTAGE."\n";
#   #warn "blah: ".SAP::Rfc::MyBcdToChar($str->PERCENTAGE);
# }
# my $if = $rfc->discover("Z_TNRO_TEST");
# $rfc->callrfc($if);
# foreach my $row ($if->tab('TTNRO')->hashRows()){
#   warn "TTNRO: ".Dumper($row)."\n";
# }
 return $cnt >=1 ? 1 : 0;

}
