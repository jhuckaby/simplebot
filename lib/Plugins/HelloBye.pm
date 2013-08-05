package SimpleBot::Plugin::HelloBye;

##
# HelloBye.pm
# SimpleBot Plugin
# Copyright (c) 2013 Joseph Huckaby
# MIT Licensed
##

use strict;
use base qw( SimpleBot::Plugin );
use Tools;

sub init {
	my $self = shift;
	$self->register_commands('hello', 'bye');
}

sub hello {
	# register greeting
	my ($self, $greeting, $args) = @_;
	
	$self->{data}->{greets} ||= {};
	if ($greeting) {
		$self->{data}->{greets}->{ $args->{who} } = $greeting;
		$self->dirty(1);
		return "Okay ".$args->{who_disp}.", I'll remember to say your greeting when you join.";
	}
	else {
		delete $self->{data}->{greets}->{ $args->{who} };
		$self->dirty(1);
		return "Okay ".$args->{who_disp}.", I'll no longer greet you.";
	}
}

sub bye {
	# register leave
	my ($self, $leave, $args) = @_;
	
	$self->{data}->{leaves} ||= {};
	if ($leave) {
		$self->{data}->{leaves}->{ $args->{who} } = $leave;
		$self->dirty(1);
		return "Okay ".$args->{who_disp}.", I'll remember to say that when you leave.";
	}
	else {
		delete $self->{data}->{leaves}->{ $args->{who} };
		$self->dirty(1);
		return "Okay ".$args->{who_disp}.", I'll no longer say goodbye to you.";
	}
}

sub chanjoin {
	# called when a user joins one of our channels
	my ($self, $args) = @_;
	
	if ($self->{data}->{greets} && $self->{data}->{greets}->{ $args->{who} }) {
		$self->say( channel => nch($args->{channel}), body => $self->{data}->{greets}->{ $args->{who} } );
	}
}

sub chanpart {
	# called when a user leaves one of our channels
	my ($self, $args) = @_;
	
	if ($self->{data}->{leaves} && $self->{data}->{leaves}->{ $args->{who} }) {
		$self->say( channel => nch($args->{channel}), body => $self->{data}->{leaves}->{ $args->{who} } );
	}
}

sub nick_change {
	# called when a user nick changes
	my ($self, $args) = @_;
	
	if ($self->{data}->{greets} && $self->{data}->{greets}->{ $args->{old_nick} }) {
		$self->{data}->{greets}->{ $args->{new_nick} } = $self->{data}->{greets}->{ $args->{old_nick} };
		delete $self->{data}->{greets}->{ $args->{old_nick} };
		$self->dirty(1);
	}
	
	if ($self->{data}->{leaves} && $self->{data}->{leaves}->{ $args->{old_nick} }) {
		$self->{data}->{leaves}->{ $args->{new_nick} } = $self->{data}->{leaves}->{ $args->{old_nick} };
		delete $self->{data}->{leaves}->{ $args->{old_nick} };
		$self->dirty(1);
	}
}

1;
