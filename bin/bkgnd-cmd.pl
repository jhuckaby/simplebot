#!/usr/bin/perl

# SimpleBot Background Restarter

use strict;
use FileHandle;
use File::Basename;
use Cwd qw/abs_path/;
use English qw( -no_match_vars ) ;
use POSIX qw/:sys_wait_h setsid/;

my $cmd = join(' ', @ARGV);
my $base_dir = dirname(dirname(abs_path($0)));

# fork to immediately return control to calling terminal
# and detach child from terminal
my $pid = fork();
if (!defined($pid)) { die( "Error: Cannot fork daemon process: $!\n" ); }
if ($pid) { exit(0); }

setsid();
open( STDIN, "</dev/null" );
open( STDOUT, ">/dev/null" );
# chdir( '/' );
# umask( 0 );

chdir( $base_dir );
exec("bin/simplebotctl.sh $cmd");
exit(0);

1;
