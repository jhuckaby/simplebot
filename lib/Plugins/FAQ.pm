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
# !faq delete mychaninfo
##

use strict;
use base qw( SimpleBot::Plugin );
use Time::HiRes qw/time/;
use Tools;

sub init {
	my $self = shift;
	$self->register_commands('faq', 'faqview');
}

sub faq {
	# register faq command
	my ($self, $msg, $args) = @_;
	my $username = lc($args->{who});
	my $chan = nch($args->{channel});
	
	if ($chan eq '#msg') { return "$username: The FAQ system only works in #channels."; }
	
	my $commands = $self->{bot}->{_eb_commands};
	
	if ($msg =~ /^list$/i) {
		# list all faqs for this channel
		$self->{data}->{channels} ||= {};
		my $faqs = $self->{data}->{channels}->{ sch($chan) } ||= {};
		
		if (!scalar keys %$faqs) {
			return "$username: There are no FAQ commands set for $chan.";
		}
		
		return "FAQ commands set for $chan: " . join(', ', sort keys %$faqs);
	}
	
	elsif ($msg =~ /^search\s+(.+)$/i) {
		# search faq keys
		my $keyword = trim($1);
		$self->{data}->{channels} ||= {};
		my $faqs = $self->{data}->{channels}->{ sch($chan) } ||= {};
		my $results = [];
		foreach my $key (sort keys %$faqs) {
			if ($key =~ m@$keyword@i) { push @$results, $key; }
		}
		
		if (scalar @$results) {
			return "FAQ Commands matching $keyword: " . join(', ', @$results);
		}
		else {
			return "No FAQ commands found matching: $keyword";
		}
	}
	
	elsif ($msg =~ /^(delete|del|remove|rem)\s+(.+)$/i) {
		# delete faq
		my $which = lc($2);
		
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
		
		if (!$faqs->{$which}) {
			return "$username: ERROR: Could not locate FAQ with name '$which' for channel $chan.";
		}
		
		delete $faqs->{$which};
		$self->dirty(1);
		
		return "$username: FAQ command '$which' deleted from $chan.";
	} # delete
	
	elsif ($msg =~ /^(set\s*)?\!?(\w+)\s+(.+)$/i) {
		my ($faq, $text) = ($2, $3);
		$faq = lc($faq);
		
		# make sure command isn't registered to another plugin
		if ($commands->{$faq}) {
			return "$username: That command is already registered to another bot plugin (".$commands->{$faq}->{name}.")";
		}
		
		# save faq name and text
		$self->{data}->{channels} ||= {};
		my $faqs = $self->{data}->{channels}->{ sch($chan) } ||= {};
		$faqs->{$faq} = $text;
		$self->dirty(1);
		
		return "$username: FAQ command '$faq' saved for channel $chan.";
	}
	
	else {
		return "$username: Incorrect syntax for !faq command.  See !help faq.";
	}
}

sub faqview {
	# register faq command
	my ($self, $msg, $args) = @_;
	
	# no-op command, just here to handle permissions
}

sub said {
	# called for everything everyone says, command or no
	my ($self, $args) = @_;
	my $chan = nch($args->{channel});
	
	if ($args->{is_command}) {
		my $faq = $args->{is_command};
		
		$self->{data}->{channels} ||= {};
		my $channel_data = $self->{data}->{channels}->{ sch($chan) } ||= {};
		
		if ($channel_data->{$faq}) {
			# check access
			if (!$self->{bot}->check_user_access($args->{who}, $self->{bot}->{_eb_data}->{plugin_access}->{faqview}, $args->{channel})) {
				$args->{body} = $args->{raw_body} = "Access Denied: ".$args->{who}." does not have ".$self->{bot}->{_eb_data}->{plugin_access}->{faqview}." access for viewing FAQs in " . $args->{channel};
				$self->say( $args );
				return;
			} # access denied
			
			my $resp = '';
			if ($args->{cmd_value} =~ /\S/) { $resp = trim($args->{cmd_value}) . ": "; } # throw faq at a foe
			$resp .= $channel_data->{$faq};
			$args->{body} = $args->{raw_body} = $resp;
			$self->say( $args );
			
			# if faq value is a bot command, invoke it
			my $regexp = $self->{bot}->{_eb_activator_re};
			if ($resp =~ s@^$regexp@@) {
				my $bot_resp = $self->{bot}->said( $args );
				if ($bot_resp) {
					$args->{body} = $args->{raw_body} = $bot_resp;
					$self->say( $args );
				}
			}
		} # found faq
	} # is command
}

1;
