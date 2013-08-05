package SimpleBot::Plugin::Points;

##
# Points.pm
# SimpleBot Plugin
# Copyright (c) 2013 Joseph Huckaby
# MIT Licensed
#
# !award jhuckaby +50
# !deduct jhuckaby 50
# !scores (10)
##

use strict;
use base qw( SimpleBot::Plugin );
use Tools;

sub init {
	my $self = shift;
	$self->register_commands('award', 'deduct', 'scores', 'points');
}

sub points {
	# umbrella command for all the other commands
	my ($self, $cmd, $args) = @_;
	my $username = $args->{who};
	
	if ($cmd =~ /^(\w+)(.*)$/) {
		my ($sub_cmd, $value) = ($1, $2);
		$value = trim($value);
		if ($self->can($sub_cmd)) { return $self->$sub_cmd($value, $args); }
		else { return "$username: Unknown points command: $sub_cmd"; }
	}
	
	return undef;
}

sub award {
	# award points to a user
	my ($self, $msg, $args) = @_;
	my $username = $args->{who};
	my $chan = $args->{channel};
	
	if ($msg =~ /^(\w+)\s+(.+)$/) {
		my ($target_nick, $amount) = ($1, $2);
		$amount = trim($amount);
		my $action = 'award';
		my $force = 0;
		
		if ($amount =~ s/\s+force$//i) { $force = 1; }
		if ($amount !~ /^(\+|\-)?\d+$/) { return "$username: Invalid syntax, please specify a number of points to award or deduct."; }
		if ($amount =~ /^\-(\d+)$/) { $amount = 0 - int($1); $action = 'deduct'; }
		if (!$amount) { return "$username: Invalid syntax, please specify a number of points to award or deduct."; }
		
		# validate nick
		my $eb_channel = $self->{bot}->{_eb_channels}->{ sch(lc($chan)) } || {};
		if (!$eb_channel->{lc($target_nick)} && !$force) {
			return "$username: Cannot give points to unknown nick '$target_nick' (unless you use force).";
		}
		
		$self->{data}->{users} ||= {};
		$self->{data}->{users}->{ lc($target_nick) } += int($amount);
		if ($self->{data}->{users}->{ lc($target_nick) } < 1) {
			delete $self->{data}->{users}->{ lc($target_nick) };
		}
		$self->dirty(1);
		
		$self->emote(
			channel => nch($chan), 
			body => ($action eq 'award') ?
				"$username awarded $amount points to $target_nick!  Yay!" :
				"$username deducted $amount points from $target_nick.  Ouch."
		);
	}
	else { return "$username: Invalid syntax, please use: !award NICKNAME POINTS"; }
	
	return undef;
}

sub deduct {
	# deduct points from a user
	my ($self, $msg, $args) = @_;
	my $username = $args->{who};
	
	if ($msg =~ /^(\w+)\s+(\+|\-)?(\d+)(.*)$/) {
		my ($target_nick, $direction, $amount, $after) = ($1, $2, $3, $4);
		$amount = 0 - int($amount);
		return $self->award( "$target_nick $amount $after", $args );
	}
	else { return "$username: Invalid syntax, please use: !deduct NICKNAME POINTS"; }
}

sub scores {
	# show scoreboard
	my ($self, $max, $args) = @_;
	my $username = $args->{who};
	my $chan = $args->{channel};
	
	my $users = $self->{data}->{users} ||= {};
	if (!scalar keys %$users) { return "$username: No points have been awarded."; }
	
	if ($max =~ /clear/i) {
		$self->{data}->{users} = {};
		$self->dirty(1);
		return "$username: The score list has been cleared.";
	}
	
	if (($max !~ /^\d+$/) || !$max) { $max = 10; }
	
	my $body = "Top $max Scores:\n";
	my $idx = 1;
	foreach my $target_nick (reverse sort { $users->{$a} <=> $users->{$b} } keys %$users) {
		my $points = $users->{$target_nick} || 0;
		$body .= "$idx. $target_nick: $points points\n";
		$idx++; if ($idx > $max) { last; }
	}
	$self->emote( channel => nch($chan), body => $body );
	
	return undef;
}

1;
