package SAP::SOAP;

use strict;
#  Super class from SAP::Rfc - This module is basically a few
#  added extensions for translation of SOAP xml blobs too and 
#  from SAP::Iface objects

use vars qw/@ISA/;

@ISA = ('SAP::Rfc');
use SAP::Rfc;
use SAP::Iface;
use XML::Parser;  	
use Data::Dumper;

use SOAP::Lite;


use vars qw($VERSION);

$VERSION = '0.01';


use vars qw($SOAPLiteMode);

$SOAPLiteMode = undef;


# Global definition of SAP rfc namespace
use vars qw($NAMESPACE);
$NAMESPACE = " xmlns:rfc=\"urn:sap-com:document:sap:rfc:functions\"";


# decode a SOAP packet into a SAP::Iface object
sub soapRequest {

  my ( $self, $xml ) = @_;

# An alternate constructor is to pass the SAP::Iface object a SOAP
#   XML Object
  my $soap = "";
  if ( $SAP::SOAP::SOAPLiteMode ){
    $soap = $xml;
  } else {
    eval {
      $soap = SOAP::Deserializer->deserialize( $xml );
    };
    return $self->soapFault( 'Server', 
                              "XML::Parser of SOAP request failed",
  			      "ERROR: $@" ) if $@;
  };
  my $name = $soap->dataof("/Envelope/Body/[1]")->name();
  print STDERR "NAME IS: ".$name ."\n";
  my ( $rfcname ) = $soap->dataof("/Envelope/Body/[1]")->name() =~ /.*\:(.*?)$/;
  print STDERR "RFCNAME THING: ".$soap->dataof("/Envelope/Body/[1]")->name()."\n";
  print STDERR "RFCNAME IS: ".$rfcname ."\n";

  # Grab the cached interface or discover a new one
  my $iface = $self->{'INTERFACES'}->{$rfcname} || "";
  if ( ! $iface ) {
    eval {
  	$iface = $self->discover( $rfcname || $name );
      };
    return $self->soapFault( 'Server', 
                              "SAP::Rfc discover of $rfcname failed",
  			      "ERROR: $@" ) if $@;
  };
  $iface->reset;

  # Process each of the parameters
  foreach my $data ( $soap->dataof("/Envelope/Body/".$name.'/*') ){
    if ( $iface->isTab($data->name) ){
      my $struct = $iface->tab($data->name)->structure;
# process each row
      my @rows = ();
      foreach my $row ( $soap->dataof("/Envelope/Body/".$name.'/'.$data->name.'/*') ){
          map {
	    eval { $struct->fieldValue( $_, $row->value->{$_}); };
          return $self->soapFault( 'Server', 
                                    "Encoded parameter field not found: ".$data->name." - $_",
	                            "ERROR: $@" ) if $@;
	        } ( $struct->fields );
	  push( @rows, $struct->value );
      };
      $iface->tab($data->name)->rows(\@rows);
    } else {
# is it a complex parameter
      my $struct = "";
      eval {
        $struct = $iface->parm($data->name)->structure;
      };
      return $self->soapFault( 'Server', 
                                "Encoded parameter not found: ".$data->name,
	                	"ERROR: $@" ) if $@;
      if ( $struct ){
      map {
        eval { $struct->fieldValue( $_, $data->value->{$_}); };
        return $self->soapFault( 'Server', 
                                  "Encoded parameter field not found: ".$data->name." - $_",
                                  "ERROR: $@" ) if $@;
	        } ( $struct->fields );
	      $iface->parm($data->name)->intvalue( $struct->value );
	  } else {
# Simple Parameter
              eval {
	        $iface->parm($data->name)->value($data->value);
	      };
              return $self->soapFault( 'Server', 
                                        "Encoded parameter not found: ".$data->name,
		                	"ERROR: $@" ) if $@;
	  };
      };
  }

  return $iface;
}


# do the SOAP call
sub soapCall {

  my ( $self, $xml ) = @_;

  my $iface  = $self->soapRequest( $xml );
  return ( $iface, 1) if ! ref( $iface );

  print STDERR "Abount to do the call: ". Dumper( $iface )."\n";
  # Now we have a complete Interface object - do the call
  eval {
    $self->callrfc( $iface );
  };
  print STDERR "After the call: ". Dumper( $iface )."\n";
  return $self->soapFault( 'Server', 
                            "SAP::Rfc call of ".$iface->name." failed",
			    "ERROR: $@" )
        if $@;

  # transform the call into a SOAP response object and return
  return $SAP::SOAP::SOAPLiteMode ? $iface : $self->soapResponse( $iface );

}

#  Encode the current interface definition into a SOAP 
#    Response - this takes all data currently in the Interface
#    and wraps it in SOAP XML
#    This partners a new instantiation mechanism for the  SAP::Iface object
#    Where the object can be passed a SOAP XML request that will be
#    parsed and translated into an interface definition to be called
#    via SAP::Rfc
sub soapResponse {

  my ( $self, $iface ) = @_;

  my $start_content = <<ENDOFHDR;
<?xml version="1.0" encoding="ISO-8859-1"?>
<SOAP-ENV:Envelope xmlns:xsi="http://www.w3.org/1999/XMLSchema-instance"
                   xmlns:SOAP-ENC="http://schemas.xmlsoap.org/soap/encoding/" 
		   xmlns:xsd="http://www.w3.org/1999/XMLSchema"
		   SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"
		   xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
  <SOAP-ENV:Body>
ENDOFHDR

    my $end_content = <<ENDOFTRL;
  </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
ENDOFTRL

  # modify the RFC name to cope with SAP namespaces
  my $intrfc = $iface->name();
  $intrfc =~ s/\//\_\-/g;
  my $xml_out = "<rfc:".$intrfc.$NAMESPACE.">\n";

  map{ 
      my $p = $_;
      $xml_out.= "   <" . $p->name .">";
      if ( $p->structure ){
          my $flds = $p->value(); 
	  $xml_out.= "\n";
	  map {  $xml_out.= "     <$_>".$flds->{$_}."<\/$_>\n" ;
	           } ( keys %{$flds} );
      } else {
	  $xml_out.= $p->value;
      };
      $xml_out.= "    <\/" . $p->name . ">\n" ;
  } ( $iface->parms );
  map{ my $tab = $_;
       $xml_out.= "   <" . $tab->name . ">\n";
       foreach my $row ( $tab->hashRows ){
	   $xml_out .= "     <item>\n"; 
	   map {  $xml_out .= "     <$_>$row->{$_}<\/$_>\n" } keys %{$row};
	   $xml_out .= "    <\/item>\n"; 
       }; 
       $xml_out.= "   <\/" . $tab->name . ">\n" 
       } ( $iface->tabs );

  $xml_out .= "<\/rfc:".$intrfc.">\n";

  # empty the interface as we dont want all this space hanging arround
  $iface->reset;

  return $start_content.$xml_out.$end_content; 

}

#  Generate a fault message
sub soapFault {
  my ($self, $faultcode, $faultstring, $result_desc) = @_;

  if ( $SOAPLiteMode ){
    die SOAP::Fault->faultcode($faultcode)
                   ->faultstring($faultstring)
                   ->faultdetail(bless {code => 1} => $result_desc)
                   ->faultactor('http://www.ompa.net/soapfault');
  };
#  faultcodes:
#    SOAP-ENV:MustUnderstand <- failing to honour mandatory header
#    SOAP-ENV:Server <- failing to handle body
  my $response_content = <<EOFFAULT;
<?xml version="1.0" encoding="ISO-8859-1"?>
<SOAP-ENV:Envelope xmlns:xsi="http://www.w3.org/1999/XMLSchema-instance"
                   xmlns:SOAP-ENC="http://schemas.xmlsoap.org/soap/encoding/" 
		   xmlns:xsd="http://www.w3.org/1999/XMLSchema"
		   SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"
		   xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
  <SOAP-ENV:Body>
      <SOAP-ENV:Fault>
         <faultcode>SOAP-ENV:$faultcode</faultcode>
	 <faultstring>$faultstring</faultstring>
	 <detail>$result_desc</detail>
      </SOAP-ENV:Fault>
  </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
EOFFAULT

 my $response_content_length = length $response_content;

#    $response_header_writer->('Content-Type', 'text/xml');
#    $response_header_writer->('Content-Length', $response_content_length);
#    $response_content_writer->($response_content);
  return $response_content;
}



=head1 NAME

SAP::SOAP - Perl extension to translate to and from SOAP calls

=head1 SYNOPSIS

  use SAP::SOAP;
  $rfc = new SAP::SOAP(
		      ASHOST   => 'myhost',
		      USER     => 'ME',
		      PASSWD   => 'secret',
		      LANG     => 'EN',
		      CLIENT   => '200',
		      SYSNR    => '00',
		      TRACE    => '1' );


my $sr =<<EOF;
<?xml version="1.0" encoding="iso-8859-1"?>
<SOAP-ENV:Envelope SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/envoding/" 
                   xmlns:xsd="http://www.w3c.org/1999/XMLSchema" 
		   xmlns:xsi="http://www.w3c.org/1999/XMLSchema-instance">
  <SOAP-ENV:Body>
<rfc:RFC_READ_TABLE xmlns:rfc="urn:sap-com:document:sap:rfc:functions">
   <DELIMITER>|</DELIMITER>
   <QUERY_TABLE>TRDIR                         </QUERY_TABLE>
   <ROWCOUNT>5</ROWCOUNT>
   <ROWSKIPS>0</ROWSKIPS>
   <FIELDS>
   </FIELDS>
   <DATA>
   </DATA>
   <OPTIONS>
     <item>
     <TEXT>NAME LIKE 'RS%'                                                         </TEXT>
    </item>
   </OPTIONS>
</rfc:RFC_READ_TABLE>
  </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
EOF

print $rfc->soapCall( $sr );

$rfc->close();



=head1 DESCRIPTION

  The best way to discribe this package is to give a brief over view, and
  then launch into several examples.


=head1 METHODS:

soapRequest
   Translate a SOAP request into an SAP::Iface object ready for
   a call via SAP::Rfc.

soapCall
   Accepts a SOAP request, processes the SAP RFC and provides a SOAP
   response or fault.
  
soapFault
   Accepts fault code, fault string, and a fault description - Returns
   a SOAP fault response.


=head1 AUTHOR

Piers Harding, piers@ompa.net.

But Credit must go to all those that have helped.


=head1 SEE ALSO

perl(1), SAP::Rfc(3), SAP::Iface(3), SOAP::Lite(3).

=cut

1;

