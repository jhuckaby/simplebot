package SimpleBot::Plugin::FAQ;

##
# FAQ.pm
# SimpleBot Plugin
# Register custom commands to emit text.
#
# !faq NAME TEXT
# !faq mychaninfo Visit our channel's website at http://mychannel.com/
# !mychaninfo
##

use strict;
use base qw( SimpleBot::Plugin );
use Time::HiRes qw/time/;
use Tools;

sub init {
	my $self = shift;
	$self->register_commands('faq');
	
	# register all faq commands for all channels
	$self->{data}->{channels} ||= {};
	foreach my $chan (keys %{$self->{data}->{channels}}) {
		my $channel_data = $self->{data}->{channels}->{$chan} ||= {};
		$self->register_commands( keys %$channel_data );
	}
}

sub faq {
	# register faq command
	my ($self, $msg, $args) = @_;
	my $username = lc($args->{who});
	my $chan = nch($args->{channel});
	
	my $commands = $self->{bot}->{_eb_commands};
	my $access = $self->{bot}->{_eb_data}->{plugin_access};
	
	if ($msg =~ /^(set\s*)?\!?(\w+)\s+(.+)$/) {
		my ($faq, $text) = ($2, $3);
		$faq = lc($faq);
		
		# make sure command isn't registered to another plugin
		if ($commands->{$faq} && ($commands->{$faq}->{name} ne $self->{name})) {
			return "$username: That command is already registered to another bot plugin (".$commands->{$faq}->{name}.")";
		}
		
		# save faq name and text
		$self->{data}->{channels} ||= {};
		my $channel_data = $self->{data}->{channels}->{ sch($chan) } ||= {};
		$channel_data->{$faq} = $text;
		$self->dirty(1);
		
		# register command
		$commands->{$faq} = $self;
		$access->{$faq} = $self->{config}->{Access}->{Default};
		
		return "$username: FAQ command '$faq' saved for channel $chan.";
	}
	else {
		return "$username: Incorrect syntax for !faq command.  See !help faq.";
	}
}

sub handler {
	# generic handler for all custom faqs
	my ($self, $faq, $value, $args) = @_;
	my $username = lc($args->{who});
	my $chan = nch($args->{channel});
	
	$self->{data}->{channels} ||= {};
	my $channel_data = $self->{data}->{channels}->{ sch($chan) } ||= {};
	
	if ($channel_data->{$faq}) {
		return $channel_data->{$faq};
	}
	
	return undef;
}

1;
