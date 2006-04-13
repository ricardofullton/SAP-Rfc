#!/usr/bin/perl
use strict;
use lib '../blib/lib';
use lib '../blib/arch';
use SAP::Rfc;
use Data::Dumper;

print STDERR "VERSION: ".$SAP::Rfc::VERSION ."\n";

#   get a list of report names from table TRDIR and 
#   then get the source code of each


my $rfc = new SAP::Rfc(
              ASHOST   => 'seahorse',
              USER     => 'developer',
              PASSWD   => 'developer',
              GETSSO2  => '1',
              LANG     => 'EN',
              CLIENT   => '010',
              SYSNR    => '00',
              TRACE    => '1' );



my $ticket = $rfc->getTicket();

warn "Error in getting Ticket: ".$rfc->error."\n" if $rfc->error;

warn "Ticket: $ticket\n" if $ticket;

$rfc->close();
