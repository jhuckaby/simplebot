package SimpleBot::Plugin::Last;

##
# Last.pm
# SimpleBot Plugin
# Report when a user was last seen in a channel.
#
# !last NICKNAME
##

use strict;
use base qw( SimpleBot::Plugin );
use Time::HiRes qw/time/;
use Tools;

sub init {
	my $self = shift;
	$self->register_commands('last');
}

sub last {
	# last seen
	my ($self, $msg, $args) = @_;
	my $username = lc($args->{who});
	my $chan = nch($args->{channel});
	
	my $users = $self->{bot}->{_eb_temp}->{channels}->{sch($args->{channel})}->{users} || {};
	if ($users->{$username}) {
		my $last_said = $users->{$username}->{last_said};
		my $now = time();
		my $elapsed = $now - $last_said->{when};
		my $nice_when = ($elapsed < 1) ? "a moment" : get_text_from_seconds(int($elapsed));
		return "User $username was last seen in $chan $nice_when ago: " . $last_said->{raw_body};
	}
	else {
		return "User $username has not been seen recently in $chan.";
	}
}

1;
