#!/usr/bin/perl

# SimpleBot Uninstaller
# by Joseph Huckaby
# Copyright (c) 2013 EffectSoftware.com

use strict;
use FileHandle;
use File::Basename;
use English qw( -no_match_vars ) ;

if ($UID != 0) { die "Error: Must be root to uninstall SimpleBot.  Exiting.\n"; }

if (yesno("\nAre you sure you want to COMPLETELY DELETE SimpleBot,\nincluding all configuration, data and logs?", "n")) {
	print "Uninstalling SimpleBot...\n";
	
	exec_shell("/etc/init.d/simplebotd stop");
	
	exec_shell("rm -f /etc/rc*.d/*simplebotd");
	exec_shell("rm -f /etc/init.d/simplebotd");
	exec_shell("rm -rf /opt/simplebot");
	print "\nUninstall complete.\n\n";
}
else {
	print "Aborted.  Will not uninstall.\n\n";
}

exit(0);

sub exec_shell {
	my $cmd = shift;
	print "Executing command: $cmd\n";
	print `$cmd 2>&1`;
}

sub yesno {
	my $text = shift;
	my $default = shift || '';

	if (prompt("$text (y/n) ", $default) =~ /y/i) { return 1; }
	return 0;
}

sub prompt {
	my $text = shift;
	my $default = shift || '';
		
	print "$text";
	if ($text !~ /(\s|\/)$/) { print ": "; }
	if ($default) { print "[$default] "; }
	my $input = <STDIN>;
	chomp $input;
	return $input || $default;
}

1;
