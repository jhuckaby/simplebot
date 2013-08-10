package SimpleBot::Plugin::Admin;

##
# Admin.pm
# SimpleBot Plugin
# Copyright (c) 2013 Joseph Huckaby
# MIT Licensed
##

use strict;
use base qw( SimpleBot::Plugin );
use Tools;

sub init {
	my $self = shift;
	$self->register_commands('test', 'repeat', 'save', 'access', 'owner', 'activator', 'status', 'say', 'emote', 'join', 'leave', 'eval', 'exec', 'quit', 'restart', 'identify', 'register', 'config', 'nick', 'msg', 'version', 'upgrade');
}

sub test {
	my ($self, $value, $args) = @_;
	return join("\n", (1..20));
}

sub repeat {
	my ($self, $value, $args) = @_;
	
	if ($value =~ s/^(\d+)\s+//) {
		my $count = $1;
		$value .= "\n";
		return ($value x $count);
	}
}

sub save {
	# force immediate data save
	my ($self, $unused, $args) = @_;
	$self->{bot}->save_data();
	return "Data saved.";
}

sub access {
	# set or get user min access level for any command
	my ($self, $value, $args) = @_;
	my $response = undef;
	
	if ($value =~ /^set\s+(\w+)\s+(0|voice|half|op|admin|founder|owner)$/i) {
		# set access level
		my ($cmd, $level) = ($1, $2);
		$cmd = lc($cmd);
		$level = lc($level);
		if (defined($self->{bot}->{_eb_data}->{plugin_access}->{$cmd})) {
			$self->{bot}->{_eb_data}->{plugin_access}->{$cmd} = $level;
			$self->dirty(1);
			$response = "User access for command '".uc($cmd)."' set to: $level+";
		}
		else { $response = "Unknown command: $cmd"; }
	}
	elsif ($value =~ /^get\s+(\w+)$/i) {
		# get access level for command
		my $cmd = lc($1);
		if (defined($self->{bot}->{_eb_data}->{plugin_access}->{$cmd})) {
			my $level = $self->{bot}->{_eb_data}->{plugin_access}->{$cmd};
			$response = "User access for command '".uc($cmd)."': $level+";
		}
		else { $response = "Unknown command: $cmd"; }
	}
	elsif ($value =~ /list/i) {
		# list access levels for all commands
		# reply in priv msg
		my @lines = ();
		foreach my $cmd (sort keys %{$self->{bot}->{_eb_data}->{plugin_access}}) {
			my $level = $self->{bot}->{_eb_data}->{plugin_access}->{$cmd};
			push @lines, uc($cmd) . ": $level+";
		}
		if ($args->{channel} ne 'msg') {
			$response = "Your requested access level list was sent to you as a private message, " . $args->{who_disp} . ".";
		}
		my $text = "Access levels for all commands:\n" . join("\n", @lines);
		$self->log_debug(9, "Saying in private message to " . $args->{who_disp} . ": $text");
		$self->{bot}->say({
			'body' => $text,
			'who' => $args->{who_disp},
			# 'address' => 'msg',
			'channel' => 'msg'
		});
	}
	
	return $response;
}

sub owner {
	# list, add, remove bot owners (auto-full privs in bot's eyes)
	my ($self, $value, $args) = @_;
	my $response = undef;
	
	if ($value =~ /^add\s+(\w+)$/i) {
		my $username = lc($1);
		if (!$self->{bot}->{_eb_data}->{owners}->{$username}) {
			$self->{bot}->{_eb_data}->{owners}->{$username} = 1;
			$self->dirty(1);
			$response = "User '$username' has been added as a bot owner.";
		}
		else { $response = "User '$username' is already a bot owner."; }
	}
	elsif ($value =~ /remove\s+(\w+)$/i) {
		my $username = lc($1);
		if ($self->{bot}->{_eb_data}->{owners}->{$username}) {
			delete $self->{bot}->{_eb_data}->{owners}->{$username};
			$self->dirty(1);
			$response = "User '$username' has been removed from the bot owner list.";
		}
		else { $response = "Username '$username' is not a bot owner."; }
	}
	elsif ($value =~ /list/i) {
		$response = "Current bot owners: " . join(', ', sort keys %{$self->{bot}->{_eb_data}->{owners}});
	}
	
	return $response;
}

sub activator {
	# list, add or remove bot activator symbols
	my ($self, $value, $args) = @_;
	my $response = undef;
	
	if ($value =~ /^add\s+(\W)$/i) {
		my $activator = $1;
		if (!$self->{bot}->{_eb_data}->{activators}->{$activator}) {
			$self->{bot}->{_eb_data}->{activators}->{$activator} = 1;
			$self->{bot}->setup_activators();
			$self->dirty(1);
			$response = "New bot activator symbol added: $activator";
		}
		else { $response = "Activator symbol already added: $activator"; }
	}
	elsif ($value =~ /^remove\s+(\W)$/i) {
		my $activator = $1;
		if ($self->{bot}->{_eb_data}->{activators}->{$activator}) {
			if (scalar keys %{$self->{bot}->{_eb_data}->{activators}} > 1) {
				delete $self->{bot}->{_eb_data}->{activators}->{$activator};
				$self->{bot}->setup_activators();
				$self->dirty(1);
				$response = "Bot activator symbol removed: $activator";
			}
			else { $response = "ERROR: Cannot delete the final bot activator symbol."; }
		}
		else { $response = "Bot activator symbol not found: $activator"; }
	}
	elsif ($value =~ /list/i) {
		$response = "Current bot activator symbols: " . join(' ', keys %{$self->{bot}->{_eb_data}->{activators}});
	}
	
	return $response;
}

sub status {
	# get status for a user
	my ($self, $username, $args) = @_;
	my $info = $self->{bot}->get_user($username, $args->{channel});
	my $response = "";
	
	my $user_status = "0 (basic)";
	foreach my $level ('founder', 'admin', 'op', 'half', 'voice') {
		if ($info->{$level}) { $user_status = $level; last; }
	}
	$response .= "$username status: $user_status";
	
	if ($self->{bot}->{_eb_data}->{owners}->{$username}) {
		$response .= " (+bot owner)";
	}
	
	return $response;
}

sub say {
	# puppet mode
	my ($self, $value, $args) = @_;
	
	if (ref($value)) { die; }
	
	if ($value =~ /^\#(\w+)\s+/) {
		my $channel = $1;
		$self->log_debug(6, "Saying into $channel: $value");
		$self->{bot}->say({
			'body' => $value,
			# 'who' => $args->{who_disp},
			# 'address' => 'msg',
			'channel' => nch($channel)
		});
	}
	else { return $value; }
}

sub nick {
	# change our own nick
	my ($self, $new_nick, $args) = @_;
	
	# save echo context for any notices sent our way after this
	$self->{echo_context} = $args;
	
	$self->log_debug(3, "Changing nick to: $new_nick");
	$self->irc_cmd( 'nick', $new_nick );
	
	$self->{bot}->{params}->{nick} = $new_nick;
	$self->{bot}->save_config();
	
	return undef;
}

sub msg {
	# send custom message to any user
	my ($self, $value, $args) = @_;
	
	if ($value =~ /^(\w+)\s+(.+)$/) {
		my ($target_nick, $msg) = ($1, $2);
		
		# save echo context for any notices sent our way after this
		$self->{echo_context} = $args;
		
		$self->{bot}->say(
			who => $target_nick,
			channel => 'msg',
			body => $msg
		);
	}
	
	return undef;
}

sub identify {
	# identify with nickserv
	my ($self, $value, $args) = @_;
	$self->log_debug(6, "Attempting to identify with NickServ");
	
	if ($value !~ /\S/) {
		# password not specified on command, so grab it from data or config
		$value = $self->{params}->{password};
	}
	else {
		# password WAS specified, so save it for next time
		$self->{bot}->{params}->{password} = $value;
		$self->{bot}->save_config();
	}
	if (!$value) {
		return "ERROR: No password on file for bot.";
	}
	
	# save echo context for any notices sent our way after this
	$self->{echo_context} = $args;
	
	$self->{bot}->say(
		who => 'NickServ',
		channel => 'msg',
		body => 'IDENTIFY ' . $value
	);
	
	return undef;
}

sub register {
	# register with nickserv
	my ($self, $value, $args) = @_;
	$self->log_debug(6, "Attempting to register with NickServ");
	
	if ($value !~ /\S/) { $value = $self->{params}->{password} . ' ' . $self->{params}->{email}; }
	
	# save echo context for any notices sent our way after this
	$self->{echo_context} = $args;
	
	$self->{bot}->say(
		who => 'NickServ',
		channel => 'msg',
		body => 'REGISTER ' . $value
	);
	
	return undef;
}

sub noticed {
	# This is like said, except for notices instead of normal messages.
	my $self = shift;
	my $args = shift;
	my $who = $args->{who} || $args->{raw_nick};
	$who =~ s/\!.+$//;
	
	if (($args->{channel} eq 'msg') && $self->{echo_context}) {
		$self->{bot}->say(
			%{$self->{echo_context}},
			body => "Received notice from $who: " . $args->{body}
		);
	}
}

sub emote {
	# puppet mode
	my ($self, $value, $args) = @_;
	
	if (ref($value)) { die; }
	
	if ($value =~ s/^\#(\w+)\s+//) {
		my $channel = $1;
		$self->log_debug(6, "Emoting into $channel: $value");
		$self->{bot}->emote({
			'body' => $value,
			# 'who' => $args->{who_disp},
			# 'address' => 'msg',
			'channel' => $channel
		});
	}
	else {
		my $channel = $args->{channel};
		$self->log_debug(6, "Emoting into $channel: $value");
		$self->{bot}->emote({
			'body' => $value,
			# 'who' => $args->{who_disp},
			# 'address' => 'msg',
			'channel' => $channel
		});
	}
	return undef;
}

sub join {
	# join a new channel
	my ($self, $channel, $args) = @_;
	$self->log_debug(3, "Joining channel: $channel");
	# $self->{bot}->join( sch($channel) );
	$self->{bot}->irc_cmd( 'join', nch($channel) );
	
	$self->{bot}->{_eb_data}->{autojoin} ||= {};
	$self->{bot}->{_eb_data}->{autojoin}->{ sch($channel) } = 1;
	$self->dirty(1);
	
	return undef;
}

sub leave {
	# leave a channel
	my ($self, $channel, $args) = @_;
	if (!$channel) { $channel = $args->{channel}; }
	$self->log_debug(3, "Leaving channel: $channel");
	# $self->{bot}->join( sch($channel) );
	$self->{bot}->irc_cmd( 'part', nch($channel) );
	
	$self->{bot}->{_eb_data}->{autojoin} ||= {};
	delete $self->{bot}->{_eb_data}->{autojoin}->{ sch($channel) };
	$self->dirty(1);
	
	return undef;
}

sub eval {
	# eval raw per code
	my ($self, $code, $args) = @_;
	
	if (!$self->{bot}->{_eb_data}->{owners}->{$args->{who}}) {
		$self->log_debug(9, "Security Warning: Non-owner trying to eval code: " . json_compose($args));
		return undef;
	}
	
	$self->log_debug(6, "Executing raw code: $code");
	
	my $response = eval $code;
	if ($@) { $response = "ERROR: $@"; }
	elsif (ref($response)) { $response = json_compose($response); }
	return $response;
}

sub exec {
	# exec raw shell command
	my ($self, $cmd, $args) = @_;
	
	if (!$self->{bot}->{_eb_data}->{owners}->{$args->{who}}) {
		$self->log_debug(9, "Security Warning: Non-owner trying to exec shell cmd: " . json_compose($args));
		return undef;
	}
	
	$self->log_debug(6, "Executing shell command: $cmd");
	
	my $response = trim(`$cmd 2>&1`);
	
	if ($response =~ /\S/) {
		foreach my $line (split(/\n/, $response)) {
			if ($line =~ /\S/) {
				$args->{body} = $line;
				$self->{bot}->say( $args );
			}
		}
	}
	return undef;
}

sub quit {
	# shut down the bot
	my ($self, $unused, $args) = @_;
	$self->log_debug(2, "Shutting down");
	$self->{bot}->shutdown( $self->{bot}->quit_message() );
}

sub restart {
	# restart the bot
	my ($self, $unused, $args) = @_;
	$self->log_debug(2, "Restarting");
	$self->{bot}->{_do_restart} = 1;
	$self->{bot}->shutdown( $self->{bot}->quit_message() );
}

sub config {
	# get or set configuration values for plugins
	# !config set server 127.0.0.1
	# !config clear trust
	# !config set Weather/APIKey cxs2x8wb5eh8mydgf74qa4s
	# !config set Twitter/AccessTokenSecret BqF4txQFOWvdgwxdKxaviJlx91gI6Xprks763j
	my ($self, $cmd, $args) = @_;
	my $username = $args->{who};
	
	if ($cmd =~ /^set\s+(\w+)\s+(.+)$/i) {
		# set global config param
		my ($key, $value) = ($1, $2);
		
		$self->{bot}->{params}->{$key} = $value;
		$self->{bot}->save_config();
		
		print "$username: Bot configuration value set and saved.";
	}
	elsif ($cmd =~ /^set\s+(\w+)\s*$/i) {
		# clear global config param
		my $key = $1;
		
		$self->{bot}->{params}->{$key} = "";
		$self->{bot}->save_config();
		
		print "$username: Bot configuration value cleared and saved.";
	}
	elsif ($cmd =~ /^get\s+(\w+)\s*$/i) {
		# get global config param
		my $key = $1;
		
		if (defined($self->{bot}->{params}->{$key})) {
			my $value = $self->{bot}->{params}->{$key};
			return "$username: $key: $value";
		}
		else { return "$username: Config parameter '$key' not found." };
	}
	elsif ($cmd =~ /^set\s+([\w\-\.]+)\/([\w\-\.]+)\s+(.+)$/i) {
		# set plugin configuration param
		my ($plugin_name, $key, $value) = ($1, $2, $3);
		
		if (!$self->{bot}->{_eb_plugin_index}->{$plugin_name}) {
			return "$username: Plugin '$plugin_name' not found.";
		}
		
		$self->{bot}->{_eb_data}->{plugin_config}->{$plugin_name} ||= {};
		$self->{bot}->{_eb_data}->{plugin_config}->{$plugin_name}->{$key} = $value;
		$self->dirty(1);
		
		# set in actual plugin object too
		my $plugin = $self->{bot}->{_eb_plugin_index}->{$plugin_name};
		$plugin->{config}->{$key} = $value;
		
		# notify plugin that config has changed
		if ($plugin->can('config_changed')) {
			$plugin->config_changed();
		}
		
		return "$username: Plugin configuration value set and saved.";
	}
	elsif ($cmd =~ /^get\s+([\w\-\.]+)\/([\w\-\.]+)\s*$/i) {
		# get plugin config param
		my ($plugin_name, $key) = ($1, $2);
		
		if (!$self->{bot}->{_eb_plugin_index}->{$plugin_name}) {
			return "$username: Plugin '$plugin_name' not found.";
		}
		
		my $value = $self->{bot}->{_eb_plugin_index}->{$plugin_name}->{config}->{$key} || '';
		return "$username: $plugin_name/$key: $value";
	}
	
	return undef;
}

sub version {
	# check local and remote version (call home)
	my ($self, $cmd, $args) = @_;
	my $username = $args->{who};
	my $version = $self->{bot}->{version};
	my $lines = [];
	
	my $short_build_id = substr($version->{BuildID}, 0, 8);
	push @$lines, 'This is SimpleBot version ' . $version->{Major} . '-' . $version->{Minor} . ' (' . $version->{Branch} . " branch, build $short_build_id)";
	# push @$lines, "(Build ID: " . $version->{BuildID} . ")";
	
	my $resp = wget('http://effectsoftware.com/software/simplebot/version-'.$version->{Branch}.'.json', 5);
	if ($resp->is_success()) {
		my $json = eval { json_parse( $resp->content() ) };
		if ($json && $json->{version}) {
			if ($json->{id} ne $version->{BuildID}) {
				push @$lines, "A newer ".$version->{Branch}." version of SimpleBot is available! (v" . $json->{version} . '-' . $json->{build} . ')';
				push @$lines, "Use the UPGRADE command to upgrade the bot, i.e. '!upgrade'";
			}
			else {
				push @$lines, "Your software is up to date.";
			}
		}
		else { 
			push @$lines, "Unable to parse version information on EffectSoftware.com: $@"; 
		}
	}
	else {
		push @$lines, "Unable to determine latest version on EffectSoftware.com: " . $resp->status_line();
	}
	
	foreach my $line (@$lines) {
		if ($line =~ /\S/) {
			$args->{body} = $line;
			$self->{bot}->say( $args );
		}
	}
	return undef;
}

sub upgrade {
	# upgrade to latest version in current branch, OR switch branches
	# !upgrade
	# !upgrade branch
	my ($self, $branch, $args) = @_;
	my $username = $args->{who};
	my $version = $self->{bot}->{version};
	if ($branch !~ /\S/) { $branch = $version->{Branch}; }
	
	my $resp = wget('http://effectsoftware.com/software/simplebot/version-'.$branch.'.json', 5);
	if (!$resp->is_success()) {
		return "Unable to determine latest $branch version on EffectSoftware.com: " . $resp->status_line();
	}
	
	# make sure only one upgrade is happening at a time
	my $upgrade_lock_file = 'logs/upgrade.lock';
	if (-e $upgrade_lock_file) {
		return "ERROR: An upgrade operation is already in progress.";
	}
	touch($upgrade_lock_file);
	
	my $shell_cmd = "install/bkgnd-upgrade.pl $branch >/dev/null 2>&1 &";
	$self->log_debug(1, "Executing upgrade script now: $shell_cmd");
	`$shell_cmd`;
	
	return "Bot is going down for upgrade.  Will be back in a few minutes!";
}

1;
