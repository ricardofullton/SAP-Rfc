package Apache::SAPSOAPServer;
use lib '/home/piers/code/saprfc/lib';

use Apache::Reload;

use SOAP::Transport::HTTP;

my $server = SOAP::Transport::HTTP::Apache
  -> objects_by_reference(qw(Apache::SAPSOAP))
  -> dispatch_to(qw(Apache::SAPSOAP))
  # enable compression support
  -> options({compress_threshold => 10000})
; 
sub handler { $server->handler(@_) }

1;
