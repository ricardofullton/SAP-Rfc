use ExtUtils::MakeMaker;

# FIND POSSIBLE RFC INSTALLATIONS
my @POSSIBLE_RFC_DIRS = qw(/usr/sap/rfcsdk /usr/local /usr);

# the ADDITIONAL_LIBS needs to be modified for each OS flavour - the rfcsdk
# has the information regarding where libs and incs resides for each
# system type

#This example information comes from the readme in the rfcsdk
#HP-UX : 
#=======
#cc -Ae -I .../rfcsdk/include -L .../rfcsdk/lib
#   sapinfo.c -o sapinfo -lrfc -lcl -ldld -lM
#
#AIX (RS/6000):
#==============
#cc -I .../rfcsdk/include -L .../rfcsdk/lib
#   sapinfo.c -o sapinfo -lrfc
#
#SINIX (RM600): 
#==============
#/opt/C/bin/cc -I .../rfcsdk/include -L .../rfcsdk/lib
#   sapinfo.c -o sapinfo -lrfc -lsocket -lnsl -lusc -ldl -lm
#
#DEC AlphaOSF:
#=============
#cc -std1 -unsigned -I .../rfcsdk/include -L .../rfcsdk/lib
#  sapinfo.c -o sapinfo -lrfc -lots -lm
#
#SUN (SunPro) :
#==============
#/opt/SUNWspro/bin/cc -Xc -xcg92 -I .../rfcsdk/include -L .../rfcsdk/lib
#    sapinfo.c -o sapinfo -lrfc -lsocket -lnsl -ldl -lm -lw

# This SHOULD work for most cases (well at least Win32, and Linux)
my $ADDITIONAL_LIBS = '-lm -ldl -lpthread ';

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
#  inorder for the linktype dynamic to work, perl must be built with
#  threads, and the rfc library included - see running Configure for perl

use File::Basename qw(dirname basename);
use Getopt::Long;
use vars qw($opt_source $opt_addlibs $opt_help);

&GetOptions("source=s", \$opt_source, "addlibs=s", \$opt_addlibs, "help", \$opt_help);

# spew forth the help
if ($opt_help){
print <<HELP;

==================================================================
BUILDING HELP
==================================================================

Hello - you obviously need Help! :-)

The whole trouble with the build process is one 
of determining what your OS is, and which RFC
library needs to be linked in, and where that 
library lives.

To help with this there are two command line
options that you can use to point me in the 
right direction:

(1) --source /usr/sap/rfcsdk
  This tells me where to look for your installed
  RFCSDK.  This must be the directory that contains
  the ./lib and ./include directories of the RFCSDK
  In the include directory must be saprfc.h etc.
  By default, this looks in /usr/sap/rfcsdk.
  librfccm is taken in preference to librfc.

(2) --addlibs ' -lm -ldl -lpthread '
  This tells me what additional libraries need to
  be passed in at link time - this can be anything
  that you would put in LDFLAGS.
  By default this is ' -lm -ldl -lpthread '

Example:

perl Makefile.PL --source /opt/rfcsdk --addlibs '-lsomethingwacky'

==================================================================

HELP
;
  exit;
}



$ADDITIONAL_LIBS = $opt_addlibs if $opt_addlibs;
unshift(@POSSIBLE_RFC_DIRS, $opt_source) if $opt_source;

my $currdir = dirname($0) || '.';
chdir($currdir) || die("can't change to $currdir: $!");
if($^O eq 'MSWin32') {
    unshift(@POSSIBLE_RFC_DIRS, 'C:/Program Files/SAP/FrontEnd/SAPgui/rfcsdk', 'c:/rfcsdk');
}

my @CANDIDATE;
my $dir;
for $dir (@POSSIBLE_RFC_DIRS) {
    next unless -d $dir;
    my $candidate = Candidate($dir);
    next unless $candidate && $candidate->[2];
    push(@CANDIDATE, $candidate);
}

if (@CANDIDATE == 1) {
    my($dir, $inc_dir, $lib) = @{$CANDIDATE[0]};
    print "Found $lib installed in $dir\n";
} elsif (@CANDIDATE > 1) {
    print "Found the following librfc (or librfccm) installations:\n";
    for (@CANDIDATE) {
    my($dir, $inc_dir, $lib) = @$_;
      print "\t$lib\t$dir\n";
    }
}

my $RFC_DIR;
if($opt_source && (@CANDIDATE == 1) && $CANDIDATE[0][0]) {
    $RFC_DIR = $CANDIDATE[0][0];
    print "Using --source librfc candidate found at $RFC_DIR\n";
} else {
    if($ARGV[0] =~ /^[a-z]\:|^\//i) {
    $RFC_DIR = shift;
    } else {
    unless($CANDIDATE[0][0]) {
          print "No librfc installation found, usually in $POSSIBLE_RFC_DIRS[0]\n";
    }
    $RFC_DIR = prompt "Which librfc build path do you want to link against?", $CANDIDATE[0][0];
    }
  }

my $candidate = &Candidate($RFC_DIR);
unless($candidate) {
    warn "Apparently no librfc installation at '$RFC_DIR'\nAre you sure you got it correct????\n"
      unless -f "$RFC_DIR/include/saprfc.h";
}
$candidate ||= ["$RFC_DIR", "$RFC_DIR/include", 'rfc'];
  
$RFC_INC = "$RFC_DIR/include";
  
if($^O =~ /Win32/) {
    unless($RFC_DIR =~ /^[a-zA-Z]\:/) {
    # default drive c
    $RFC_DIR = "c:".$RFC_DIR;
    }
    unless($RFC_INC =~ /^[a-zA-Z]\:/) {
      # default drive c
      $RFC_INC = "c:".$RFC_INC;
    }
    $RFC_INC = "\"$RFC_INC\"";
    $RFC_DIR =~ s|/|\\|g;
    $RFC_INC =~ s|/|\\|g;

    # patch from Ben Laurie
    if(-d "$RFC_DIR/lib") {
      $RFC_LIB = "-L\"$RFC_DIR/lib\"";
    } elsif(-d "$RFC_DIR/out32dll") {
    $RFC_LIB = "-L\"$RFC_DIR\\out32dll\"";
    }else {
    # Allow developers to point at librfc source...
    $RFC_LIB = "-L\"$RFC_DIR\"";
    }

    $SEP = "\\";
    $LIBS = ' -l'.$candidate->[2];
} else {
    $RFC_LIB = "-L".$RFC_DIR."/lib";
    $SEP = "/";
    $LIBS = ' -l'.$candidate->[2];
  
    # ccc on alpha support
    if ($^O eq 'linux' && `uname -m` =~ /alpha/ &&
    !(system("nm $RFC_DIR/lib/librfc.a|grep -q 'U _Ots'")>>8)) {
    $LIBS .= ' -lots'; 
    }
}

my $candidate_info = join('; ', @$candidate);

  
print <<INFO;

================================================
BUILD INFORMATION
================================================

rfc dir:        $RFC_DIR
libraries:      $ADDITIONAL_LIBS $RFC_LIB $LIBS
include dir:    $RFC_INC
rfc header:     $RFC_INC/saprfc.h
rfc candidate:  $candidate_info

================================================

INFO
;


WriteMakefile(
    clean => { 'FILES'    => './examples/*.trc *.inl *.trc testconn ./examples/testconn *~ core test*.txt *.tar.gz _Inline ./examples/_Inline' },
    dist => { 'TARFLAGS'    => 'cvf',
              'COMPRESS'        => 'gzip -9f',
            'SUFFIX'    => '.tgz'},
    'AUTHOR' => 'Piers Harding <piers@cpan.org>',
    'ABSTRACT' => 'Perl extension for performing RFC Function calls
    agains an SAP R/3 System',

    'LINKTYPE'    => 'dynamic',
    'VERSION_FROM'    => 'Rfc.pm',
    'NAME'    => 'SAP::Rfc',
     DEFINE => '-D'.(($^O =~ /aix/i)? 'DOIBMWKRND' : 'SUMITELSE'),

    'LIBS'      => ["$ADDITIONAL_LIBS $RFC_LIB $LIBS"],
    'INC'    => "-I".$RFC_INC,

);

sub MY::makefile { '' }

sub MY::processPL { '' }


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


sub Candidate {
    my $dir = shift;
    my $inc_dir;
    my @libs = ();

    for (
     "$dir/include/saprfc.h"
    ) 
      {
      if(-e $_) {
          $version_file = $_;
      } 
      }
    return unless defined $version_file;

    #$open_rfc = ($version_file =~ /openrfc/) ? 1 : 0;
    my $dirname = $inc_dir = dirname($version_file);
    return unless (-e "$dirname/saprfc.h");

    # Silly test to look for the library files
    my $libd = (-d "$dir/out32dll") ? 'out32dll' : 'lib';
    if (opendir(LIBDIR, "$dir/$libd")) {
    while (defined($_ = readdir(LIBDIR))) {
        push(@libs, 'rfc32') if /rfc32/i;
        push(@libs, 'rfccm') if /^librfccm/;
        push(@libs, 'rfc') if /^librfc/;
    }
    closedir(LIBDIR);
    }
    warn "$dir/lib does not seem to contain the librfc (or librfccm) library files\n"
    unless scalar @libs;
    @libs = reverse sort @libs;

    [$dir, $inc_dir, shift @libs];
}

