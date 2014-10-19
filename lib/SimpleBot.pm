package Bot::BasicBot::SimpleBot;

use strict;
use FileHandle;
use File::Basename;
use Bot::BasicBot;
use Data::Dumper;
use HTTP::Date;
use URI::Escape;
use Time::HiRes qw/time/;
use POE;
use Encode qw(decode encode);

use Tools;
use Plugin;
use VersionInfo;

# our @ISA = ("Bot::BasicBot");
use base qw( Bot::BasicBot );

sub run {
	# overriding Bot::BasicBot::run()
	# so we can add 'irc_raw' state to catch notices from spoofed nicks
	my $self = shift;

	# create the callbacks to the object states
	POE::Session->create(
		object_states => [
			$self => {
				_start => "start_state",
				die	=> "die_state",

				irc_001		  => "irc_001_state",
				irc_msg		  => "irc_said_state",
				irc_public	   => "irc_said_state",
				irc_ctcp_action  => "irc_emoted_state",
				irc_notice	   => "irc_noticed_state",

				irc_disconnected => "irc_disconnected_state",
				irc_error		=> "irc_error_state",

				irc_join		 => "irc_chanjoin_state",
				irc_part		 => "irc_chanpart_state",
				irc_kick		 => "irc_kicked_state",
				irc_nick		 => "irc_nick_state",
				irc_quit		 => "irc_quit_state",

				fork_close	   => "fork_close_state",
				fork_error	   => "fork_error_state",

				irc_366		  => "names_done_state",

				irc_332		  => "topic_raw_state",
				irc_topic		=> "topic_state",

				irc_shutdown	 => "shutdown_state",

				tick => "tick_state",
				
				irc_raw => "irc_raw_state" # ADDED THIS
			}
		]
	);

	# and say that we want to recive said messages
	$poe_kernel->post($self->{IRCNAME}, 'register', 'all');

	# run
	$poe_kernel->run() if !$self->{no_run};
	return;
}

sub _fork_utf8_said {
	# modified version of Bot::BasicBot::_fork_said which decodes UTF-8
    my ($self, $body, $wheel_id) = @_[OBJECT, ARG0, ARG1];
    chomp $body;    # remove newline necessary to move data;
    
    # pick up the default arguments we squirreled away earlier
    my $args = $self->{forks}{$wheel_id}{args};
    $args->{body} = decode('UTF-8', $body, Encode::FB_QUIET);
    
    $self->say($args);
    return;
}

sub irc_raw_state {
	# catch all incoming raw IRC commands before parsing
	# look for notices and handle accordingly
	# (Bot::BasicBot seems to 'miss' notices from spoofed nicks)
	my ($self, $kernel, $session) = @_[OBJECT, KERNEL, SESSION];
	my ($raw, $args) = @_[ARG0 .. $#_];
	my $bot_nick = $self->{params}->{nick};
	
	if ($self->{params}->{echo_log}) {
		print "DEBUG: $raw\n";
	}
	
	# :NickServ NOTICE joebot :Password accepted. Nick 'joebot' has been successfully identified.
	if ($raw =~ /^\:(\w+)\s+NOTICE\s+$bot_nick\s+\:(.+)$/i) {
		# caught notice
		my ($who, $msg) = ($1, $2);
		
		$self->log_debug(9, "Caught private notice from $who: $msg");
		
		$self->invoke_all_plugins('noticed', {
			who => $who,
			channel => 'msg', # private message
			body => $msg
		});
	} # notice to us
	
	return 0;
}

sub init {
	# called when the bot is created, as part of new(). 
	# Return a true value for a successful init, or undef if you failed, in which case new() will die.
	my $self = shift;
	
	# save pid, so we can tell if we are in the parent or child fork
	$self->{_eb_parent_pid} = $$;
	
	my $version = $self->{version} = get_version();
	$self->log_debug(1, 'SimpleBot v' . $version->{Major} . '-' . $version->{Minor} . ' (' . $version->{Branch} . ') starting up');
	$self->log_debug(2, "Build ID: " . $version->{BuildID} );
	
	# create data directories
	make_dirs_for( 'data/' . $self->{params}->{server} . '/' );
	make_dirs_for( 'data/' . $self->{params}->{server} . '/queue/' );
	
	# clear out queue from last time
	my $files = [ glob( 'data/' . $self->{params}->{server} . '/queue/*.json' ) ];
	foreach my $file (@$files) { unlink $file; }
	
	# temp data (stored in RAM only)
	$self->{_eb_temp} = {};
	
	# load server data
	$self->{_eb_data} = $self->load_data();
	$self->{_eb_data}->{plugins} ||= {};
	delete $self->{_eb_data}->{dirty};
	
	# defaults
	$self->{_eb_data}->{activators} ||= {'~'=>1,'!'=>1};
	$self->setup_activators();
	
	$self->{_eb_data}->{owners} ||= {};
	if ($self->{params}->{owners}) {
		foreach my $key (keys %{$self->{params}->{owners}}) {
			$self->{_eb_data}->{owners}->{$key} = $self->{params}->{owners}->{$key};
		}
	}
	
	# store plugin user access levels and config overrides in data system
	$self->{_eb_data}->{plugin_access} ||= {};
	$self->{_eb_data}->{plugin_config} ||= {};
	
	# load all plugins
	$self->{_eb_plugins} = [];
	$self->{_eb_commands} = {};
	$self->{_eb_plugin_index} = {};
	
	my $plugin_files = [ glob('lib/Plugins/*.pm') ];
	foreach my $plugin_file (@$plugin_files) {
		my $plugin_name = basename($plugin_file); $plugin_name =~ s/\.\w+$//;
		$self->log_debug(2, "Loading Plugin: $plugin_name ($plugin_file)");
		eval { require $plugin_file; };
		if ($@) {
			my $error_msg = $@;
			$self->log_debug(1, "Plugin Crash: $plugin_file: $error_msg");
			if ($self->{params}->{echo_log}) { die "Bot could not start, as Plugin $plugin_name crashed: $error_msg\n"; }
		}
		my $plugin_config_file = "conf/Plugins/$plugin_name.xml";
		my $plugin_config = {};
		if (-e $plugin_config_file) {
			$plugin_config = parse_xml( $plugin_config_file );
			if (!ref($plugin_config)) { die $plugin_config; }
		}
		if ($self->{_eb_data}->{plugin_config}->{$plugin_name}) {
			# allow plugin config in data system to override config file
			# these are set with !config set PluginName/XMLElement Value
			foreach my $key (keys %{$self->{_eb_data}->{plugin_config}->{$plugin_name}}) {
				$plugin_config->{$key} = $self->{_eb_data}->{plugin_config}->{$plugin_name}->{$key};
			}
		}
		my $plugin_data = $self->{_eb_data}->{plugins}->{$plugin_name} ||= {};
		my $class_name = "SimpleBot::Plugin::$plugin_name";
		my $plugin = $class_name->new(
			config => $plugin_config,
			bot => $self,
			params => $self->{params},
			data => $plugin_data
		);
		$plugin->init();
		push @{$self->{_eb_plugins}}, $plugin;
		$self->{_eb_plugin_index}->{$plugin_name} = $plugin;
	} # foreach plugin
	
	# assign default permissions for commands
	# only if not set in server data
	foreach my $cmd (keys %{$self->{_eb_commands}}) {
		my $plugin = $self->{_eb_commands}->{$cmd};
		if (!defined($self->{_eb_data}->{plugin_access}->{$cmd})) {
			$self->{_eb_data}->{plugin_access}->{$cmd} = 
				defined($plugin->{config}->{Access}->{$cmd}) ? $plugin->{config}->{Access}->{$cmd} :
				$plugin->{config}->{Access}->{Default};
		}
	} # foreach command
	
	# keep track of which users are in which channels (use RAM)
	$self->{_eb_channels} = {};
	
	# load bad word list for plugins to use
	my $words = [];
	foreach my $line (split(/\n/, load_file('conf/bad_words.txt') || '')) {
		if ($line =~ /\S/) {
			$line = trim($line);
			$line =~ s/([^\w\s])/\\$1/g;
			push @$words, $line;
		}
	}
	if (scalar @$words) {
		$self->{bad_word_match} = "\\b(" . join("|", @$words) . ")s?\\b";
	}
	
	return 1;
}

sub connected {
	# An optional method to override, gets called after we have connected to the server
	my $self = shift;
	
	eval {
		$self->log_debug(2, "in connected()");
		$self->invoke_all_plugins('connected');
		
		if ($self->{params}->{password}) {
			$self->log_debug(3, "trying to idenify ourselves");
			$self->say(
				who => 'NickServ',
				channel => 'msg',
				body => 'IDENTIFY ' . $self->{params}->{password}
			);
		}
		
		# delay this for a sec, in case identify gives us perms to join private rooms, etc.
		if ($self->get_data('autojoin')) {
			$self->enqueue_task({
				Type => 'Core',
				Command => 'do_autojoin'
			});
		}
	};
	if ($@) { $self->log_debug(1, "CRASH connected: $@"); $self->shutdown( $self->quit_message() ); }
	
	# reschedule tick for 1 second, not 5
	$self->schedule_tick(1);
	
	return undef;
}

sub do_autojoin {
	# called by connected(), join delay to account for nickserv ident
	my ($self, $task) = @_;
	
	foreach my $channel (keys %{$self->get_data('autojoin')}) {
		$self->log_debug(4, "Joining channel: $channel");
		# $self->join( sch($channel) );
		$self->irc_cmd( 'join', nch($channel) );
	}
}

sub said {
	# called by default whenever someone says anything that we can hear, either in a public channel or to us in private that we shouldn't ignore.
	my $self = shift;
	my $args = shift;
	my $response = undef;
	
	eval {
		$self->log_debug(9, "in said(): " . Dumper($args));
		$self->{_eb_last_said} = $args;
		my $text = trim($args->{raw_body});
		
		# sometimes 'who' is undef, so we have to get it from 'raw_nick'
		if (!$args->{who} && $args->{raw_nick} && ($args->{raw_nick} =~ /^(\w+)/)) {
			$args->{who} = $1;
		}
		
		$args->{who_disp} = $args->{who}; # save original nick for display purposes
		$args->{who} = lc($args->{who});
		$args->{when} = time();
		
		# see if we have been given a command
		my $is_command = 0;
		my $regexp = $self->{_eb_activator_re};
		if ($text =~ s@^$regexp@@) {
			$is_command = 1;
		}
		elsif ($args->{channel} eq 'msg') {
			$is_command = 1;
		}
		
		if ($is_command) {
			if ($text =~ /^(\w+)(.*)$/) {
				my ($cmd, $value) = ($1, $2);
				$cmd = lc($cmd);
				$value = trim($value);
				
				$args->{is_command} = $cmd;
				$args->{cmd_value} = $value;
				
				if (!$self->{_eb_commands}->{$cmd}) {
					my $found = 0;
					my $chosen_cmd = '';
					foreach my $key (keys %{$self->{_eb_commands}}) {
						if ($key =~ m@^$cmd@) { $found++; $chosen_cmd = $key; }
					}
					if ($found == 1) { $cmd = $chosen_cmd; }
				}
				
				if ($self->{_eb_commands}->{$cmd}) {
					my $plugin = $self->{_eb_commands}->{$cmd};
					my $plugin_name = $plugin->{name};
					if ($self->check_user_access($args->{who}, $self->{_eb_data}->{plugin_access}->{$cmd}, $args->{channel})) {
						$self->log_debug(6, "Calling plugin $plugin_name for cmd: $cmd ($value)");
						eval {
							if ($plugin->can($cmd)) {
								$response = $plugin->$cmd( $value, $args );
							}
							elsif ($plugin->can("_$cmd")) {
								# for subs that start with digits
								$cmd = "_$cmd";
								$response = $plugin->$cmd( $value, $args );
							}
							else {
								$response = $plugin->handler( $cmd, $value, $args );
							}
						};
						if ($@) { 
							$response = "Plugin $plugin_name Crashed: $@";
							$self->log_debug(1, $response);
							$response =~ s/\n.*$//s;
						}
					} # user has access
					else {
						$response = "Access Denied: ".$args->{who}." does not have ".$self->{_eb_data}->{plugin_access}->{$cmd}." access for $plugin_name/$cmd in " . $args->{channel};
					}
				} # plugin owns command!
			} # got cmd and value
		} # is command
		
		# keep track of last said per user (in RAM only)
		$self->{_eb_temp}->{channels} ||= {};
		$self->{_eb_temp}->{channels}->{sch($args->{channel})} ||= {};
		my $users = $self->{_eb_temp}->{channels}->{sch($args->{channel})}->{users} ||= {};
		$users->{ lc($args->{who}) } ||= {};
		$users->{ lc($args->{who}) }->{last_said} = deep_copy($args);
	};
	if ($@) { $self->log_debug(1, "CRASH said: $@"); $self->shutdown( $self->quit_message() ); }
	
	$self->invoke_all_plugins('said', $args);
	
	if ($response) { $self->log_debug(9, "Response: $response"); }
	return $response;
}

sub chanjoin {
	# Called when someone joins a channel. It receives a hashref argument similar to the one received by said(). 
	# The key 'who' is the nick of the user who joined, while 'channel' is the channel they joined.
	my $self = shift;
	my $args = shift;
	
	eval {
		$self->log_debug(8, "in chanjoin(): " . Dumper($args));
		
		$args->{who} = lc($args->{who});
		
		my $channel = $self->{_eb_channels}->{ sch(lc($args->{channel})) } ||= {};
		$channel->{lc($args->{who})} = $args->{who};
		
		$self->update_room_info( $args->{channel},
			num_users => '+1'
		);
	};
	if ($@) { $self->log_debug(1, "CRASH chanjoin: $@"); $self->shutdown( $self->quit_message() ); }
	
	$self->invoke_all_plugins('chanjoin', $args);
	return undef;
}

sub chanpart {
	# Called when someone parts a channel. It receives a hashref argument similar to the one received by said(). 
	# The key 'who' is the nick of the user who parted, while 'channel' is the channel they parted.
	my $self = shift;
	my $args = shift;
	
	eval {
		$self->log_debug(8, "in chanpart(): " . Dumper($args));
		
		$args->{who} = lc($args->{who});
		
		my $channel = $self->{_eb_channels}->{ sch(lc($args->{channel})) } ||= {};
		delete $channel->{lc($args->{who})};
		
		$self->update_room_info( $args->{channel},
			num_users => '-1'
		);
	};
	if ($@) { $self->log_debug(1, "CRASH chanpart: $@"); $self->shutdown( $self->quit_message() ); }
	
	$self->invoke_all_plugins('chanpart', $args);
	return undef;
}

sub got_names {
	# Whenever we have been given a definitive list of 'who is in the channel', this function will be called. It receives a hash reference as an argument. The key 'channel' will be the channel we have information for, 'names' is a hashref where the keys are the nicks of the users, and the values are more hashes, containing the two keys 'op' and 'voice', indicating if the user is a chanop or voiced respectively.
	# $VAR1 = { 'names' => { 'joebot' => { 'voice' => 0, 'op' => 0 }, 'testnick' => { 'voice' => 0, 'op' => 1 }, 'jhuckabynick' => { 'voice' => 0, 'op' => 1 } }, 'channel' => '#myroom' };]
	my $self = shift;
	my $args = shift;
	
	eval {
		$self->log_debug(8, "in got_names(): " . Dumper($args));
	
		if ($args->{names} && ref($args->{names})) {
			
			my $channel = $self->{_eb_channels}->{ sch(lc($args->{channel})) } ||= {};
			foreach my $username (keys %{$args->{names}}) {
				$channel->{ lc($username) } = $username;
			}
			
			$self->update_room_info( $args->{channel},
				num_users => scalar keys %{$args->{names}}
			);
		}
	};
	if ($@) { $self->log_debug(1, "CRASH got_names: $@"); $self->shutdown( $self->quit_message() ); }
	
	$self->invoke_all_plugins('got_names', $args);
	return undef;
}

sub topic {
	# Called when the topic of the channel changes. It receives a hashref argument. The key 'channel' is the channel the topic was set in, and 'who' is the nick of the user who changed the channel, 'topic' will be the new topic of the channel.
	my $self = shift;
	my $args = shift;
	
	eval {
		$self->log_debug(6, "in topic(): " . Dumper($args));
	
		my $topic = $args->{topic} || $args->{channel};
		$topic =~ s/\#\w+\s+//;
	
		$self->update_room_info( $args->{channel},
			last_topic => $topic
		);
	};
	if ($@) { $self->log_debug(1, "CRASH topic: $@"); $self->shutdown( $self->quit_message() ); }
	
	$self->invoke_all_plugins('topic', $args);
	return undef;
}

sub nick_change {
	# When a user changes nicks, this will be called. It receives a hashref which will look like this:
	# { from => "old_nick", to => "new_nick", }
	my $self = shift;
	my $args = { old_nick => shift @_, new_nick => shift @_ };
	
	eval {
		$self->log_debug(8, "in nick_change(): " . Dumper($args));
		
		$args->{old_nick} = lc($args->{old_nick});
		$args->{new_nick} = lc($args->{new_nick});
		
		foreach my $channel_id (keys %{$self->{_eb_channels}}) {
			my $channel = $self->{_eb_channels}->{$channel_id};
			if ($channel->{lc($args->{old_nick})}) {
				delete $channel->{lc($args->{old_nick})};
				$channel->{lc($args->{new_nick})} = $args->{new_nick};
			}
		}
	};
	if ($@) { $self->log_debug(1, "CRASH nick_change: $@"); $self->shutdown( $self->quit_message() ); }
	
	$self->invoke_all_plugins('nick_change', $args);
	return undef;
}

sub kicked {
	# Called when a user is kicked from the channel. It receives a hashref which will look like this:
	# { channel => "#channel", who => "nick", kicked => "kicked", reason => "reason", }
	my $self = shift;
	my $args = shift;
	
	eval {
		$self->log_debug(7, "in kicked(): " . Dumper($args));
		
		$args->{kicked} = lc($args->{kicked});
		$args->{who} = lc($args->{who});
	
		$self->chanpart({ 'body' => 'chanpart', 'who' => $args->{kicked}, 'address' => 'chan', 'channel' => $args->{channel} });
	};
	if ($@) { $self->log_debug(1, "CRASH kicked: $@"); $self->shutdown( $self->quit_message() ); }
	
	$self->invoke_all_plugins('kicked', $args);
	return undef;
}

sub tick {
	# This is an event called every regularly. The function should return the amount of time until the tick event should next be called.
	my $self = shift;
	my $now = time();
	
	if (!$self->{_eb_tick}) {
		# print "first tick!\n";
		$self->{_eb_tick} = 1;
	}
	
	# commit data to disk every minute, if dirty
	if (!$self->{_last_eb_check} || (($now - $self->{_last_eb_check}) >= ($self->{params}->{data_commit_freq} || 60))) {
		$self->{_last_eb_check} = $now;
		if ($self->{_eb_data}->{dirty}) {
			$self->forkit(
				channel => 'msg',
				who => $self->{params}->{nick},
				run => sub {
					$self->save_data();
					print "\n"; # child forks always need this
				} # sub
			);
			# $self->save_data();
			delete $self->{_eb_data}->{dirty};
		} # dirty
	} # check time
	
	# monitor queue directory for child fork commands
	if (!$self->{_last_eb_queue_check} || (($now - $self->{_last_eb_queue_check}) >= 1.0)) {
		$self->{_last_eb_queue_check} = $now;
		
		# check mod date
		my $mod_date = (stat('data/' . $self->{params}->{server} . '/queue'))[9];
		if (!$self->{_last_eb_queue_mod} || ($mod_date != $self->{_last_eb_queue_mod})) {
			$self->{_last_eb_queue_mod} = $mod_date;
			
			# load all json queue files
			my $files = [ glob( 'data/' . $self->{params}->{server} . '/queue/*.json' ) ];
			foreach my $file (@$files) {
				my $task_raw = load_file($file);
				$self->log_debug(9, "Executing task file: $file: $task_raw");
				my $task = json_parse( $task_raw );
				
				# execute task
				if ($task) {
					if ($task->{Type} eq 'Plugin') {
						my $plugin_name = $task->{Plugin};
						my $func = $task->{Command};
						
						# locate correct plugin
						foreach my $plugin (@{$self->{_eb_plugins}}) {
							if ($plugin->{name} eq $task->{Plugin}) {
								# found it
								$self->log_debug(9, "Calling Plugin: $plugin_name/$func");
								eval { $plugin->$func( $task ); };
								if ($@) { $self->log_debug(1, "Plugin Crash: ".$plugin->{name}.": $func: $@"); }
								last;
							} # found plugin
						} # foreach plugin
					} # Plugin task
					elsif ($task->{Type} eq 'Core') {
						my $func = $task->{Command};
						$self->log_debug(9, "Calling Core: $func");
						eval { $self->$func( $task ); };
						if ($@) { $self->log_debug(1, "Core Crash: $func: $@"); }
					} # Core task
				} # good task
				
				unlink $file;
			} # foreach queue file
		} # mod date changed
		
		# also check for daily maint here
		my $day_code = yyyy_mm_dd( time() );
		if (!$self->{_eb_data}->{LastMaint} || ($day_code ne $self->{_eb_data}->{LastMaint})) {
			$self->run_daily_maintenance();
			
			$self->{_eb_data}->{LastMaint} = $day_code;
			$self->dirty(1);
		}
	} # check time
	
	$self->invoke_all_plugins('tick');
	return $self->{params}->{tick_freq} || 0.1;
}

sub run_daily_maintenance {
	# rotate logs, etc.
	# runs once a day at midnight
	my $self = shift;
	my $now = time();
	
	$self->log_debug(2, "Starting daily maintenance run");
	
	# allow all plugins to do maintenance
	$self->invoke_all_plugins('maint');
	
	# rotate logs into daily gzip archives
	$self->log_debug(3, "Rotating logs");
	$self->rotate_logs();
	
	$self->log_debug(2, "Daily maintenance complete");
}

sub rotate_logs {
	# rotate and archive daily logs
	my $self = shift;
	my $yyyy_mm_dd = yyyy_mm_dd( normalize_midnight( normalize_midnight(time()) - 43200 ), '/' );
	my $archive_dir = 'logs/archive';
	my $logs = [ glob('logs/*.log') ];
	my $gzip_bin = find_bin('gzip');
	
	foreach my $log_file (@$logs) {
		my $log_category = basename($log_file); $log_category =~ s/\.\w+$//;
		my $log_archive = $archive_dir . '/' . $log_category . '/' . $yyyy_mm_dd . '.log';
		
		$self->log_debug(3, "Maint: Archiving log: $log_file to $log_archive.gz");
		
		# add a message at the bottom of the log, in case someone is live tailing it.
		my $fh = FileHandle->new( ">>$log_file" );
		if ($fh) {
			my $nice_time = scalar localtime;
			$fh->print("\n# Rotating log to $log_archive.gz at $nice_time\n");
		}
		$fh->close();
		
		if (make_dirs_for( $log_archive )) {
			if (rename($log_file, $log_archive)) {
				my $output = `$gzip_bin $log_archive 2>&1`;
				if ($output =~ /\S/) {
					$self->log_debug(1, "Maint Error: Failed to gzip file: $log_archive: $output");
				}
			}
			else {
				$self->log_debug(1, "Maint Error: Failed to move file: $log_file --> $log_archive: $!");
			}
		}
		else {
			$self->log_debug(1, "Maint Error: Failed to create directories for: $log_archive: $!");
		}
	} # foreach log
}

sub help {
	# This is the text that the bot will respond to if someone simply says help to it.
	# Just passthru to said
	my $self = shift;
	my $args = shift;
	return $self->said( $args );
}

sub userquit {
	# Receives a hashref which will look like:
	# { who => "nick that quit", body => "quit message", }
	my $self = shift;
	my $args = shift;
	
	eval {
		$self->log_debug(8, "in userquit(): " . Dumper($args));
		$args->{who} = lc($args->{who});
		
		# call chanpart for all user's channels that we know of
		foreach my $channel_id (keys %{$self->{_eb_channels}}) {
			my $channel = $self->{_eb_channels}->{$channel_id};
			if ($channel->{lc($args->{who})}) {
				$self->chanpart({ 'body' => 'chanpart', 'who' => $args->{who}, 'address' => 'chan', 'channel' => nch($channel_id) });
			}
		}
	};
	if ($@) { $self->log_debug("CRASH userquit: $@"); $self->shutdown( $self->quit_message() ); }
	
	$self->invoke_all_plugins('userquit', $args);
	return undef;
}

sub invoke_all_plugins {
	# invoke named function on all plugins, pass along func args
	my $self = shift;
	my $func = shift;
	
	foreach my $plugin (@{$self->{_eb_plugins}}) {
		if ($plugin->can($func)) {
			eval { $plugin->$func( @_ ); };
			if ($@) { $self->log_debug(1, "Plugin Crash: ".$plugin->{name}.": $func: $@"); }
		}
	}
}

sub enqueue_task {
	# enqueue async task, which will be picked up and executed by tick()
	my ($self, $task) = @_;
	
	my $file = 'data/' . $self->{params}->{server} . '/queue/task-' . time() . '-' . $$ . '.json';
	my $task_raw = json_compose_pretty($task);
	$self->log_debug(9, "Enqueuing task: $file: $task_raw");
	
	save_file_atomic( $file, $task_raw );
}

sub get_data {
	# get data or key
	my $self = shift;
	my $key = shift || '';
	if ($key) { return $self->{_eb_data}->{$key}; }
	else { return $self->{_eb_data}; }
}

sub load_data {
	# load server data from disk
	my $self = shift;
	my $file = 'data/' . $self->{params}->{server} . '/data.json';
	if (-e $file) { return json_parse(load_file($file)); }
	else { return {}; }
}

sub save_data {
	# save server data to disk
	my $self = shift;
	my $file = 'data/' . $self->{params}->{server} . '/data.json';
	my $data = shift || $self->{_eb_data};
	
	$self->log_debug(9, "Saving data to: $file");
	
	# remove dirty flag
	delete $data->{dirty};
	
	save_file( $file, json_compose_pretty($data) );
}

sub save_config {
	# save config xml file back to disk
	my $self = shift;
	
	if ($self->{config_file}) {
		if (!save_file( $self->{config_file}, compose_xml($self->{params}, 'BotConfig') )) {
			$self->log_debug(1, "ERROR: Could not save config file: $!");
			return 0;
		}
	}
	
	return 1;
}

sub dirty {
	# set dirty flag
	my $self = shift;
	my $flag = shift || 0;
	$self->{_eb_data}->{dirty} = $flag;
}

sub update_data {
	# update server data, handle deltas, mark as dirty
	my $self = shift;
	my $update = {@_};
	my $xml = $self->{_eb_data};
	
	# merge changed elements in with xml
	foreach my $key (keys %$update) {
		# interpret +N and -N values to increment/decrement stats
		my $value = $update->{$key};
		# warn "\t$key: $value\n";
	
		if ($value =~ /^\+(\d+)$/) {
			# increment
			$xml->{$key} += $1;
		}
		elsif ($value =~ /^\-(\d+)$/) {
			# decrement
			$xml->{$key} -= $1;
		}
		else {
			# simple key/value copy
			$xml->{$key} = $update->{$key};
		}
	}

	$self->{_eb_data}->{dirty} = 1;
}

sub update_room_info {
	# update room specific info
	my $self = shift;
	my $channel = nch(shift @_);
	my $update = {@_};
	
	$self->{_eb_data}->{channels} ||= {};
	my $xml = $self->{_eb_data}->{channels}->{$channel} ||= {};
	
	# merge changed elements in with xml
	foreach my $key (keys %$update) {
		# interpret +N and -N values to increment/decrement stats
		my $value = $update->{$key};
		# warn "\t$key: $value\n";
	
		if ($value =~ /^\+(\d+)$/) {
			# increment
			$xml->{$key} += $1;
		}
		elsif ($value =~ /^\-(\d+)$/) {
			# decrement
			$xml->{$key} -= $1;
		}
		else {
			# simple key/value copy
			$xml->{$key} = $update->{$key};
		}
	}

	$self->{_eb_data}->{dirty} = 1;
}

sub log_debug {
	my $self = shift;
	my $level = shift;
	my $msg = shift;
	my $package = shift || 'main';
	
	if ($level > $self->{params}->{debug_level}) { return; }
	
	my $fh = new FileHandle ">>logs/debug.log";
	my $id = $self->{server};
	$id =~ s/^irc\.//i; $id =~ s/\.(com|net|org|tv|cc|co|info)$//i;
	
	$msg =~ s/\n/ /g;
	$msg =~ s/\s+/ /g;
	
	my $now = time();
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($now);
	my $nice_date = sprintf("%0004d-%02d-%02d %02d:%02d:%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec);
	
	my $line = '[' . join('][', 
		$now,
		$nice_date,
		$$,
		$id,
		$self->{nick},
		$package,
		$level,
		encode('UTF-8', trim($msg), Encode::FB_QUIET)
	) . "]\n";
		
	$fh->print( $line );
	$fh->close();
	
	if ($self->{params}->{echo_log} && ($$ == $self->{_eb_parent_pid})) { print "$line"; }
}
sub log { my $self = shift; $self->log_debug(5, @_); }

sub get_user {
	# get user info from irc
	my ($self, $username, $channel) = @_;
	
	if (!$username) { die; }
	if (!$channel) { die; }
	
	my $nicks = $self->channel_data( nch($channel) );
	my $user = $nicks->{$username} || undef;
	
	if (!$user) {
		# username might be lower-case, gah
		foreach my $nick (keys %$nicks) {
			if (lc($nick) eq $username) {
				$user = $nicks->{$nick};
				last;
			}
		}
	}
	if (!$user) { return {}; }
	
	my $irc = $self->pocoirc();
	
	$user->{half} = $irc->_nick_has_channel_mode($channel, $username, 'h') ? 1 : 0;
	$user->{admin} = $irc->_nick_has_channel_mode($channel, $username, 'a') ? 1 : 0;
	$user->{founder} = $irc->_nick_has_channel_mode($channel, $username, 'q') ? 1 : 0;
	
	return $user;
}

sub get_users {
	# get hash of users for particular channel
	# pass in channel id
	my $self = shift;
	my $channel = nch(shift @_);
	if (!$channel) { die; }
	
	my $nicks = $self->channel_data( $channel );
	my $users = {};
	my $irc = $self->pocoirc();
	
	foreach my $nick (keys %$nicks) {
		$users->{ lc($nick) } = {
			%{$nicks->{$nick}},
			half => $irc->_nick_has_channel_mode($channel, $nick, 'h') ? 1 : 0,
			admin => $irc->_nick_has_channel_mode($channel, $nick, 'a') ? 1 : 0,
			founder => $irc->_nick_has_channel_mode($channel, $nick, 'q') ? 1 : 0
		};
	}
	return $users;
}

sub check_user_access {
	# check if user is a bot admin
	my ($self, $username, $min_access, $channel) = @_;
	if (!$min_access) { return 1; } # all users have "no" access
	
	# ultimate trust mode (only for initial setup)
	if ($self->{params}->{trust} && (lc($self->{params}->{trust}) eq lc($username))) { return 1; }
	
	my $user = undef;
	if ($channel eq 'msg') {
		# private channel, scan all channels for bot AND user, use perms from there
		my $irc = $self->pocoirc();
		my $bot_nick = $self->{params}->{nick};
		my $all_channels = $irc->channels();
		
		foreach my $temp_chan (keys %$all_channels) {
			my $temp_nicks = [ $irc->channel_list($temp_chan) ];
			my $found = 0;
			
			foreach my $temp_nick (@$temp_nicks) {
				if (lc($temp_nick) eq lc($username)) { $found++; last if $found == 2; }
				if (lc($temp_nick) eq lc($bot_nick)) { $found++; last if $found == 2; }
			}
			
			if ($found == 2) {
				# found bot and user, use this channel!
				$user = $self->get_user($username, $temp_chan);
				last;
			}
		} # foreach channel
	} # private
	else {
		$user = $self->get_user($username, $channel);
	}		
	
	if (!$user) { return 0; }
	
	$username = lc($username);
	
	# bot owners always have all privileges, if and only if they are hop or higher
	if ($self->{_eb_data}->{owners}->{$username} && ($user->{admin} || $user->{op} || $user->{half})) {
		return 1;
	}
	
	if ($user->{$min_access}) { return 1; } # exact match on min req.
	if ($user->{founder}) { return 1; } # nothing higher than founder
	
	if ($min_access eq 'op') {
		if ($user->{admin}) { return 1; } # admin is higher than op.
	}
	elsif ($min_access eq 'half') {
		if ($user->{op}) { return 1; } # op is higher than half
		if ($user->{admin}) { return 1; } # admin is higher than op.
	}
	elsif ($min_access eq 'voice') {
		if ($user->{half}) { return 1; } # half is higher than voice
		if ($user->{op}) { return 1; } # op is higher than half
		if ($user->{admin}) { return 1; } # admin is higher than op.
	}
	
	return 0;
}

sub irc_cmd {
	# execute raw irc command (e.g. /nick)
	my $self = shift;
	my $cmd = shift;
	$poe_kernel->post(
        $self->{IRCNAME},
        $cmd,
        $self->charset_encode(@_),
    );
}

sub setup_activators {
	# compile activator characters into regexp
	my $self = shift;
	$self->{_eb_activator_re} = "(" . join("|", map { "\\$_"; } keys %{$self->{_eb_data}->{activators}}) . ")";
}

1;
