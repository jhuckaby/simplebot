#!/usr/bin/perl

##
# SimpleBot 1.0
# by Joseph Huckaby, 2011 - 2013
# MIT Licensed
##

use strict;
use File::Basename;
use Bot::BasicBot;
use Data::Dumper;
use JSON;
use Cwd qw/abs_path/;
use HTTP::Date;
use URI::Escape;
use POE;
use Carp ();
use DateTime;
use POSIX qw/:sys_wait_h setsid/;

$| = 1;

$SIG{'__DIE__'} = sub { Carp::cluck("Stack Trace: "); };

# figure out our base dir and cd into it
my $base_dir = dirname(dirname(abs_path($0)));
chdir( $base_dir );

# load our modules
push @INC, "$base_dir/lib";
require "$base_dir/lib/SimpleBot.pm";
eval "use Tools;";

# determine config file name
my $config_file = 'conf/config.xml';
if (@ARGV && ($ARGV[0] =~ /\.xml$/i)) {
	$config_file = shift @ARGV;
}

# process command line args
my $cmdline_args = new Args();

if (!$cmdline_args->{debug}) {
	# not running in cmd-line debug mode, so fork daemon process, write pid file
	become_daemon();
	
	# write pid file
	save_file( 'logs/pid.txt', $$ );
	
	# cleanup after upgrade
	unlink('logs/upgrade.lock');
}

# main loop
my $done = 0;
while (!$done) {
	my $params = {};
	
	$params = parse_xml( $config_file );
	if (!ref($params)) { die $params; }
	
	foreach my $key (keys %$cmdline_args) {
		$params->{$key} = $cmdline_args->{$key};
	}
	
	if ($cmdline_args->{debug}) {
		$params->{echo_log} = 1;
		$params->{debug_level} = 9;
	}
	
	# $params->{server}   ||= 'irc.effectgames.com';
	# $params->{port}     ||= '6667';
	# $params->{channel}  ||= '#test';
	# $params->{nick}     ||= 'joebot';
	# $params->{username} ||= 'joebot';
	# $params->{name}     ||= 'JoeBot';
	# $params->{password} ||= '12345';
	# $params->{activator} ||= '~';
	
	my $bot = Bot::BasicBot::SimpleBot->new(
		
		params => $params,
		config_file => $config_file,
		
		server => $params->{server},
		port	 => $params->{port},
		password => $params->{server_password} || undef,
		# channels => [ split(/\s+/, $params->{channel}) ],
		channels => [],
		
		nick			=> $params->{nick},
		# alt_nicks => ["bbot", "simplebot"],
		username	=> $params->{username},
		name			=> $params->{name},
		
		# ignore_list => [qw(dipsy dadadodo laotse)],
		
		charset => "utf-8", # charset the bot assumes the channel is using
		
		# send messages to IRC at FULL SPEED
		flood => $params->{flood} || 0,
		
		# test
		ssl => $params->{ssl} || 0
	);

	$bot->log_debug( "Params: " . Dumper($params) );

	# print "Features: " . Dumper($bot->{features});

	$SIG{'INT'} = $SIG{'TERM'} = sub {
		local $SIG{ALRM} = sub { die "Shutdown Timeout\n" };
		alarm 5;
		$bot->shutdown( $bot->quit_message() ); 
	};

	$bot->run();
	
	# force data save
	$bot->save_data();
	
	# restart or quit
	if ($bot->{_do_restart}) {
		delete $bot->{_do_restart};
		$bot->log_debug(2, "Restarting");
		$done = 0;
		sleep 1;
	}
	else {
		$bot->log_debug(2, "Exiting");
		$done = 1;
	}
}

$SIG{'__DIE__'} = undef;
unlink('logs/pid.txt');

exit;

sub become_daemon {
	##
	# Fork daemon process and disassociate from terminal
	##
	my $pid = fork();
	if (!defined($pid)) { die "Error: Cannot fork daemon process: $!\n"; }
	if ($pid) { exit(0); }
	
	setsid();
	open( STDIN, "</dev/null" );
	open( STDOUT, ">/dev/null" );
	umask( 0 );
	
	return $$;
}

1;
