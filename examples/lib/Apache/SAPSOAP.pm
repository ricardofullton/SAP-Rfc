package Apache::SAPSOAP;
use strict;

use vars qw(@ISA);
@ISA = qw(SOAP::Server::Parameters);

use Apache::Constants qw(OK DECLINED NOT_FOUND REDIRECT BAD_REQUEST);
use Apache::Reload;
use lib '/web/perllib';
use lib '/home/piers/code/saprfc/lib';


use SAP::SOAP;

use vars qw($VERSION $AUTOLOAD);

my $times = 0;


# Autoload the RFC Function name ( SOAP Method )
sub AUTOLOAD {

  my $self = shift;
  my @parms = @_;
  my $name = $AUTOLOAD;
  $name =~ s/.*://;

# Autoload RFC Function
   $self->method( $name, @parms );

}


# use something to pull the config
use SAP::Config qw(/home/piers/code/saprfc/examples/);
my %config = SAP::Config::get();

# global connection object to SAP
use vars qw($rfc);

check_connect( $config{'sap'} );

# Fatal error on load if no SAP system
die  "SAPSOAP: Cannot connect to SAP System: $config{sap}->{ashost} \n" 
        unless $rfc;


sub method {
 
  my ( $package, $method, @parms ) = @_;
  my $request = pop( @parms );

  # check that this RFC is allowed to be called as per the 
  #  configuration
  die SOAP::Fault->faultcode("SAPSOAP.ForbiddenRFC")
                   ->faultstring("RFC Call Forbidden")
                   ->faultdetail(bless {code => 1} => "RFC $method is Forbidden  due to configuration")
                   ->faultactor('http://www.ompa.net/soapfault')
		   if ! exists $config{'rfc'}->{$method};
#

  # set the internal flag that makes SAP::SOAP behave for 
  #  SOAP::Lite
  $SAP::SOAP::SOAPLiteMode = 1;

  print STDERR "Doing the call ...\n";
  # refresh the SAP connection
  check_connect( $config{'sap'} );
  print STDERR "Connection is fine ...\n";

  # process the call
  my $response =  $rfc->soapCall( $request );
#  print STDERR "Done  SAP RFC SOAP Call ",$response->tab('DATA')->rows(),"...\n";
  print STDERR "Done  SAP RFC SOAP Call ".$times ++ ."...\n";

  # create SOAP::Lite data objects for return
  my @parms = ();
  eval {
  use SOAP::Lite;
  import SOAP::Data 'name';
  map{ 
      my $p = $_;
      if ( $p->structure ){
           my $flds = $p->value(); 
 	   push( @parms, name( $p->name => $flds ) );
       } else {
 	   push( @parms, name( $p->name => $p->value ) );
       };
   } ( $response->parms );
  map{ my $tab = $_;
       push( @parms, SOAP::Data->name( $tab->name )->type('array')->value(
                           \name( 'item' =>
                                        ( $tab->hashRows )
                                )
                         )
           )
     } ( $response->tabs );

  };
  # empty the interface as we dont want all this space hanging arround
  $response->reset;
  
  return @parms;

}


# Connect to the SAP System
sub check_connect {

  my $config = shift;

  if ( ! $rfc ){
    print STDERR "SAPSOAP: Creating a new connection to: ".$config->{'ashost'}."\n";
    $rfc = new SAP::SOAP(
                         ASHOST   => $config->{'ashost'},
                         USER     => $config->{'user'},
                         PASSWD   => $config->{'passwd'},
                         LANG     => $config->{'lang'},
                         CLIENT   => $config->{'client'},
                         SYSNR    => $config->{'sysnr'},
#                         TRACE    => $config->{'trace'}
        	         );
  } elsif ( ! $rfc->is_connected ){
    print STDERR "SAPSOAP: Restarting connection to: ".$config->{'ashost'}."\n";
    $rfc = new SAP::SOAP(
                         ASHOST   => $config->{'ashost'},
                         USER     => $config->{'user'},
                         PASSWD   => $config->{'passwd'},
                         LANG     => $config->{'lang'},
                         CLIENT   => $config->{'client'},
                         SYSNR    => $config->{'sysnr'},
#                         TRACE    => $config->{'trace'}
        	         );
  } else {
#    print STDERR "SAPSOAP: Great connection to: ".$config->{'ashost'}." - using cached\n";
  };


  die  "SAPSOAP: Cannot connect to SAP System: $config->{ashost} \n" 
        unless $rfc;

}


1;


