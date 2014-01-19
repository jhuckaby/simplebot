#!/usr/bin/perl

# SimpleBot Background Updater
# Automatically invoked by IRC command
# by Joseph Huckaby
# Copyright (c) 2013 PixlCore.com

use strict;
use FileHandle;
use English qw( -no_match_vars ) ;
use POSIX qw/:sys_wait_h setsid/;
use File::Basename;
use Cwd 'abs_path';

BEGIN {
	push @INC, dirname(dirname(abs_path($0))) . "/lib";
}
use Tools;
use VersionInfo;

$| = 1;

my $base_dir = abs_path( dirname( dirname($0) ) );
my $log_file = "$base_dir/logs/upgrade.log";

if ($EUID != 0) { die( "Error: Must be root to upgrade SimpleBot (you are user $EUID).  Exiting.\n" ); }

my $current_version = get_version();
my $branch = (shift @ARGV) || $current_version->{Branch};

# fork to immediately return control to calling terminal
# and detach child from terminal
my $pid = fork();
if (!defined($pid)) { death( "Error: Cannot fork daemon process: $!\n" ); }
if ($pid) { exit(0); }

setsid();
open( STDIN, "</dev/null" );
open( STDOUT, ">/dev/null" );
# chdir( '/' );
# umask( 0 );

log_msg("Initiating upgrade for $branch");

my $script_url = "http://pixlcore.com/software/simplebot/install-latest-$branch.txt";
log_msg("Fetching URL: $script_url");
my $script_resp = wget($script_url);
if (!$script_resp->is_success()) { death("Failed to fetch URL: $script_url: " . trim($script_resp->status_line()) . "\n"); }
my $script_raw = $script_resp->content();

my $temp_file = "/var/tmp/temp-upgrade-simplebot-$branch-$$.sh";
if (!save_file($temp_file, $script_raw)) { death("Failed to save temp file: $temp_file: $!\n"); }

if (!chmod( 0775, $temp_file )) { death("Failed to chmod file: $temp_file: $!\n"); }

# exec script as a pipe, so we can capture output as it happens
log_msg("Executing installer script");
my $fh = FileHandle->new( "$temp_file 2>&1 |" );
if (!$fh) { death("Failed to open pipe to: $temp_file: $!\n"); }
my $line = undef;
while (defined($line = <$fh>)) {
	if ($line =~ /\S/) { log_msg( $line ); }
	last if $line =~ /SimpleBot Daemon started/;
}
$fh->close();

unlink $temp_file;
unlink "$base_dir/logs/upgrade.lock";
log_msg( "Upgrade complete, exiting." );

exit(0);

sub death {
	# Log error and die
	my $msg = shift;
	log_msg( "Fatal Error: $msg" );
	log_msg( "Exiting" );
	unlink "$base_dir/logs/upgrade.lock";
	die $msg;
}

sub log_msg {
	##
	# Log message to file
	##
	my $msg = shift;
	
	my $nice_msg = $msg;
	$nice_msg =~ s/^\s+//; # trim leading whitespace
	$nice_msg =~ s/\s+$//; # trim trailing whitespace
	
	if (length($nice_msg)) {
		my $nice_time = scalar localtime;
		my $line = "[" . join('][', 
			time(),
			$nice_time,
			$$
		) . "] $nice_msg\n";
		
		my $fh = new FileHandle ">>$log_file";
		if ($fh) {
			$fh->print( $line );
			$fh->close();
		}
	}
}

1;
