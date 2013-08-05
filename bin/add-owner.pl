#!/usr/bin/perl

##
# add-owner.pl
# SimpleBot v1.0 Command-line IRC owner add tool.
# Copyright (c) 2013 Joseph Huckaby and EffectSoftware.com
# Released under the MIT License.
# 
# Usage:
#	./add-owner.pl USERNAME
##

use strict;
use warnings;
use File::Basename;
use Cwd qw/abs_path/;
use URI::Escape;
use Digest::MD5 qw(md5_hex);
use English qw( -no_match_vars ) ;

BEGIN {
	push @INC, dirname(dirname(abs_path($0))) . "/lib";
}
use Tools;

$| = 1;

if ($UID != 0) { die "Error: Must be root to add SimpleBot owners.  Exiting.\n"; }

my $usage = "Usage: ./add-owner.pl USERNAME\n";

my $username = shift @ARGV or die $usage;

my $base_dir = dirname(dirname(abs_path($0)));
chdir( $base_dir );

my $pid_file = 'logs/pid.txt';
if (-e $pid_file) {
	my $pid = trim( load_file($pid_file) );
	if ($pid && kill(0, $pid)) {
		die "ERROR: Please shut down SimpleBot before adding owners, e.g. /etc/init.d/simplebotd stop\n\n";
	}
}

my $config_file = 'conf/config.xml';
my $params = parse_xml( $config_file );
if (!ref($params)) { die $params; }

my $data_file = 'data/' . $params->{server} . '/data.json';
my $data = undef;
if (-e $data_file) { $data = json_parse(load_file($data_file)); }
else { $data = {}; }

$data->{owners} ||= {};
$data->{owners}->{$username} = 1;

make_dirs_for( $data_file );
if (!save_file_atomic( $data_file, json_compose_pretty($data) )) {
	die( "ERROR: Failed to save server data: $data_file: $!\n\n" );
}

print "User '$username' has been added as a bot owner.\n";

exit();

1;
