use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
#  inorder for the linktype dynamic to work, perl must be built with
#  threads, and the rfc library included - see running Configure for perl

WriteMakefile(
    clean => { 'FILES'	=> './examples/*.trc *.inl *.trc testconn ./examples/testconn *~ core test*.txt *.tar.gz _Inline ./examples/_Inline' },
    dist => { 'TARFLAGS'	=> 'cvf',
              'COMPRESS'        => 'gzip -9f',
    		'SUFFIX'	=> '.tgz'},
    'LINKTYPE'	=> 'dynamic',
    'VERSION_FROM'	=> 'Rfc.pm',
    'NAME'	=> 'SAP::Rfc',
    'DEFINE'	=> '',

# These lines need to be modified for each UNIX flavour - the rfcsdk
# has the information regarding where libs and incs resides for each
# system type

    'LIBS'      => ['-lm -ldl -lpthread -L/usr/sap/rfcsdk/lib -lrfc'],
    'INC'       => '-I/usr/sap/rfcsdk/include',

# change these lines for win32 to point to the corresponding libs and incs dir
#    'LIBS'      => ['-lm -ldl -lpthread -LX:\pathto\rfcsdk\lib -lrfc32'],
#    'INC'       => '-IX:\pathto\rfcsdk\include',

);


# Get input values for testing
print "\n\n\n";
print "Welcome to The SAP::Rfc Object oriented Programming Interface for \n";
print "performing RFC calls to an SAP R\/3 System\.\n";
print "YOU MUST READ THE README FILE THAT COMES WITH THIS DISTRIBUTION\n";
print "AND UNDERSTAND THE TERMS AND CONDITIONS THEREIN.\n\n\n";
print "           ---------------- Please Press Enter --------------- \n";
$x=<>;
print 
    <<ENDOFTEXT;
    Copyright (c) 2002 Piers Harding.
    All rights reserved.

    This program is free software; you can redistribute it and/or modify
    it under the terms of either:

	a) the GNU General Public License as published by the Free
	Software Foundation; either version 1, or (at your option) any
	later version, or

	b) the "Artistic License" which comes with this Kit.

    This software is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See either
    the GNU General Public License or the Artistic License for more details.

    You should have received a copy of the Artistic License with this
    Kit, in the file named "Artistic".  If not, I'll be glad to provide one.

    You should also have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software Foundation,
    Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.

ENDOFTEXT

print "           ---------------- Please Press Enter --------------- \n";
$x=<>;

print "\nPlease Enter The Following:\n";
open(FIL,">testconn") or die "cant open parm file: $!";
open(FILCP,">examples/testconn") or die "cant open parm file: $!";
&get("ASHOST", "Test SAP System Hostname:","localhost");
&get("SYSNR", "System Number:","18");
&get("CLIENT", "Client Number:","000");
&get("LANG", "Login Language:","en");
&get("USER", "User Id:","DEVELOPER");
&get("PASSWD", "Password:","19920706");
&get("TRACE", "Trace Level:","1");
close FIL;
close FILCP;

print "Were on our way .............\n";

# routine for each parameter
sub get{
 my $parm = shift;
 my $parmdesc = shift;
 my $parmdefault = shift;
 print "Enter $parm - $parmdesc \[$parmdefault\] ";
 my $val = <>;
 chomp $val;
 $val =~ s/^\s*?(\S+)\s*?$/$1/;
 if ( $val !~ m/^$/ ){
   print FIL "$parm\t$val\n";
   print FILCP "$parm\t$val\n";
 } else {
   print FIL "$parm\t$parmdefault\n";
   print FILCP "$parm\t$parmdefault\n";
 };

}
