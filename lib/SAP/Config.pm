package SAP::Config;

#  This has been completely plagarised from DJ Adams
# $Id: Config.pm,v 1.2 2001/05/30 08:47:57 piers Exp $

use strict;
use vars qw($CONFIGDIR);

my %config;

sub import {
  (undef, $CONFIGDIR) = @_;

  opendir(DIR, $CONFIGDIR) or die "Cannot open config dir: $!\n";

  # Take all the *.config files in the CONFIG_DIR
  foreach my $config_file (grep { /^.+?\.config$/ } readdir(DIR)) {

    # Config type, e.g. 'ldap'
    my ($config_type) = $config_file =~ m|^(.+?)\.config$|; 

    # Open the file
    open(CONFIG, $CONFIGDIR.$config_file) or die "Cannot read $config_file: $!\n";

    # Read contents, parse into name/value pairs, and store
    while (<CONFIG>) {
      next if m/(^#|^\s*$)/; # ignore blank lines and comments
      chomp;
      my ($name, $value) = split(/\s+/, $_, 2);
      $config{$config_type}->{$name} = $value;
    }

    # Close the file
    close(CONFIG);

  }

  closedir DIR;

}


sub get {

  return %config;

}


=head1 DESCRIPTION

SAP::Config is a rip off of a module my good friend DJ Adams wrote as a generic tool for handling interface login parameters and the like.

It used the perl native import method to load up *.config files in a give directory:

use SAP::Config qw(/home/piers/code/saprfc/examples/);
my %config = SAP::Config::get();

where the keys of the first level of the hash are the names of the files in the supplied directory.

if a config file sap.config looks like:
ashost        kogut
sysnr         17
client        000
lang          EN
user          developer
passwd        secret
trace         1                                                                                                 
Then the value ashost is accessed vial $config{'sap'}->{'ashost'}.



=head1 METHODS:

get
  return a hash of the config file values.


=head1 AUTHOR

Piers Harding, piers@ompa.net.

But Credit must go to all those that have helped.


=head1 SEE ALSO

perl(1), SAP::Rfc(3), SAP::Iface(3), SOAP::Lite(3).

=cut

1;

