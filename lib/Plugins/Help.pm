package SimpleBot::Plugin::Help;

##
# Help.pm
# SimpleBot Plugin
# Copyright (c) 2013 Joseph Huckaby
# MIT Licensed
##

use strict;
use base qw( SimpleBot::Plugin );
use Tools;

sub init {
	my $self = shift;
	$self->register_commands('help');
}

sub help {
	# ask for help
	my ($self, $cmd, $args) = @_;
	my $response = undef;
	
	if ($cmd) {
		# ask for help on a specific command (plugin)
		my $plugin = $self->{bot}->{_eb_commands}->{$cmd};
		if ($plugin) {
			$response = $plugin->{config}->{Help}->{Detail}->{$cmd} || '';
			if (!$response) {
				return "Sorry, there is no help available for command: $cmd";
			}
		}
		else {
			return "Unknown command: $cmd";
		}
	}
	else {
		# generic help
		$response = trim( load_file( 'conf/help.txt' ) ) . "\n-\n";
		$response =~ s/\[(\w+)\]/ $self->{params}->{$1} || ''; /eg;
		
		foreach my $plugin (@{$self->{bot}->{_eb_plugins}}) {
			if ($plugin->{config}->{Help}->{Brief}) {
				$response .= trim($plugin->{config}->{Help}->{Brief}) . "\n";
			}
		}
		
		$response .= "\n-\nYou can type 'help COMMAND' for details about a specific command.\n";
	}
	
	if ($response) {
		# always respond in private message for help
		# $self->{bot}->irc_cmd('privmsg', $args->{who_disp}, $response);
		# return;
		
		$self->say({
			'body' => $response,
			'who' => $args->{who_disp},
			# 'address' => 'msg',
			'channel' => 'msg'
		});
		if ($args->{channel} ne 'msg') {
			return "Your requested help text was sent to you as a private message, " . $args->{who_disp} . ".";
		}
	}
	return undef;
}

1;
