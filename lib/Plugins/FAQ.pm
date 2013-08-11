package SimpleBot::Plugin::FAQ;

##
# FAQ.pm
# SimpleBot Plugin
# Register custom commands to emit text.
#
# !faq NAME TEXT
# !faq mychaninfo Visit our channel's website at http://mychannel.com/
# !mychaninfo
# !faq list
# !faq delete 1
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
	
	if ($chan eq '#msg') { return "$username: The FAQ system only works in #channels."; }
	
	my $commands = $self->{bot}->{_eb_commands};
	my $access = $self->{bot}->{_eb_data}->{plugin_access};
	
	if ($msg =~ /^(set\s*)?\!?(\w+)\s+(.+)$/i) {
		my ($faq, $text) = ($2, $3);
		$faq = lc($faq);
		
		# make sure command isn't registered to another plugin
		if ($commands->{$faq} && ($commands->{$faq}->{name} ne $self->{name})) {
			return "$username: That command is already registered to another bot plugin (".$commands->{$faq}->{name}.")";
		}
		
		# save faq name and text
		$self->{data}->{channels} ||= {};
		my $faqs = $self->{data}->{channels}->{ sch($chan) } ||= {};
		$faqs->{$faq} = $text;
		$self->dirty(1);
		
		# register command
		$commands->{$faq} = $self;
		$access->{$faq} = $self->{config}->{Access}->{Default};
		
		return "$username: FAQ command '$faq' saved for channel $chan.";
	}
	
	elsif ($msg =~ /^list$/i) {
		# list all faqs for this channel
		$self->{data}->{channels} ||= {};
		my $faqs = $self->{data}->{channels}->{ sch($chan) } ||= {};
		
		if (!scalar keys %$faqs) {
			return "$username: There are no FAQ commands set for $chan.";
		}
		
		my $response = '';
		$response = "Here are the FAQ commands set for $chan:\n";
		
		my $idx = 0;
		foreach my $faq (sort keys %$faqs) {
			my $text = $faqs->{$faq};
			$response .= "#" . int($idx + 1) . ": " . $faq . ": " . $text . "\n";
			$idx++;
		}
		
		$self->say(
			channel => nch($chan),
			body => $response
		);
		return undef;
	}
	
	elsif ($msg =~ /^(delete|del|remove|rem)\s+(.+)$/i) {
		# delete faq
		my $which = $2;
		
		$self->{data}->{channels} ||= {};
		my $faqs = $self->{data}->{channels}->{ sch($chan) } ||= {};
		
		if (!scalar keys %$faqs) {
			return "$username: There are no FAQ commands set for $chan.";
		}
		
		if ($which =~ /all/i) {
			$self->{data}->{channels}->{ sch($chan) } = {};
			$self->dirty(1);
			return "$username: All FAQ commands deleted for $chan.";
		}
		if ($which !~ /^\d+$/) {
			return "$username: Invalid syntax.  Please specify the FAQ number to delete.  Type !faq list to see a list of them.";
		}
		
		my $faq_keys = [ sort keys %$faqs ];
		my $faq_key = $faq_keys->[ int($which) - 1 ] || '';
		if (!$faq_key) {
			return "$username: FAQ index '$which' not found.  Type !faq list to see a list of them.";
		}
		
		delete $faqs->{$faq_key};
		$self->dirty(1);
		
		return "$username: FAQ command \#$which deleted.";
	} # delete
	
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
