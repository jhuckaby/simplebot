package SimpleBot::Plugin::AutoKick;

##
# AutoKick.pm
# SimpleBot Plugin
# Copyright (c) 2014 Joseph Huckaby
# MIT Licensed
##

use strict;
use base qw( SimpleBot::Plugin );
use Tools;

sub init {
	my $self = shift;
	$self->register_commands('autokick');
	$self->rebuild_regexps();
}

sub autokick {
	# add, delete or list kick strings
	my ($self, $msg, $args) = @_;
	my $username = lc($args->{who});
	my $chan = nch($args->{channel});
	
	if ($chan eq '#msg') { return "$username: The AutoKick system only works in #channels."; }
	
	if ($msg =~ /^(add|set)\s+(.+)$/) {
		my $match = $2;
		
		$self->{data}->{channels} ||= {};
		my $kicks = $self->{data}->{channels}->{ sch($chan) } ||= {};
		$kicks->{$match} = 1;
		
		$self->rebuild_regexps($chan);
		$self->dirty(1);
		
		return "$username: Autokick text '$match' added for channel $chan.";
	}
	elsif ($msg =~ /^(delete|remove|del|rem)\s+(.+)$/) {
		my $match = $2;
		
		$self->{data}->{channels} ||= {};
		my $kicks = $self->{data}->{channels}->{ sch($chan) } ||= {};
		
		if ($kicks->{$match}) {
			delete $kicks->{$match};
		
			$self->rebuild_regexps($chan);
			$self->dirty(1);
			
			return "$username: Autokick text '$match' removed from channel $chan.";
		}
		else {
			return "$username: ERROR: Autokick text '$match' not found for channel $chan.";
		}
	}
	elsif ($msg =~ /^list$/) {
		$self->{data}->{channels} ||= {};
		my $kicks = $self->{data}->{channels}->{ sch($chan) } ||= {};
		
		if (scalar keys %$kicks) {
			return "$username: The following text will get you auto-kicked from $chan: " . join(', ', sort keys %$kicks);
		}
		else {
			return "$username: No autotext kick found for channel $chan.";
		}
	}
	else {
		return "$username: Unknown command.  Please type '!help autokick' for instructions.";
	}
}

sub said {
	# called for everything everyone says, command or no
	my ($self, $args) = @_;
	my $chan = nch($args->{channel});
	my $text = trim($args->{raw_body});
	
	# ignore if trying to use the autokick plugin
	if ($args->{is_command} && ($args->{is_command} eq 'autokick')) { return; }
	
	if ($self->{regexps}->{ sch($chan) }) {
		my $regexp = $self->{regexps}->{ sch($chan) };
		if ($text =~ m@\b$regexp\b@i) {
			# matched! auto-kick the disbeliever!
			$self->log_debug(5, "Kicking " . $args->{who_disp} . " from $chan for saying one of the autokick phrases: $regexp");
			$self->irc_cmd('kick', $chan, $args->{who_disp}, $self->{config}->{KickMessage});
		} # msg matched a kick
	} # channel has kicks
}

sub rebuild_regexps {
	# rebuild regex for scanning all messages
	my $self = shift;
	my $solo_chan = shift;
	$self->{data}->{channels} ||= {};
	$self->{regexps} ||= {};
	
	my $chans = [];
	if ($solo_chan) { $chans = [ sch($solo_chan) ]; } # rebuild single chan
	else { $chans = [ keys %{$self->{data}->{channels}} ]; } # rebuild ALL chans (init)
	
	foreach my $chan (@$chans) {
		my $kicks = $self->{data}->{channels}->{ sch($chan) } ||= {};
		if (scalar keys %$kicks) {
			$self->{regexps}->{ sch($chan) } = '(' . join('|', keys %$kicks) . ')';
		}
		else {
			delete $self->{regexps}->{ sch($chan) };
		}
	}
}

1;
