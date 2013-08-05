package SimpleBot::Plugin::Topic;

##
# Topic.pm
# SimpleBot Plugin
# Based on an original design by TMFKsoft and also used in the popular Techie-Bot, 
# these commands allow you set the room topic in pieces, so you can maintain 
# an overall persistent topic with several "columns" that you can set individually.
#
# !topic Minecraft Chat
# !towner Eric
# !tverb is
# !tstatus Away
# !tdivider |
# !tstatic http://mywebsite.com
# !ton
# !toff
# !trefresh
# !treset
##

use strict;
use base qw( SimpleBot::Plugin );
use Time::HiRes qw/time/;
use Tools;

sub init {
	my $self = shift;
	$self->register_commands('topic', 'towner', 'tverb', 'tstatus', 'tdivider', 'tstatic', 'trefresh', 'treset', 'ton', 'toff');
}

sub handler {
	# generic handler for all our sub-commands
	# topic|towner|tverb|tstatus|tdivider|tstatic|trefresh|treset|ton|toff
	my ($self, $cmd, $value, $args) = @_;
	my $username = lc($args->{who});
	my $chan = nch($args->{channel});
	
	$self->{data}->{channels} ||= {};
	my $topic = $self->{data}->{channels}->{ sch($chan) } ||= {};
	
	$topic->{topic} ||= $chan;
	$topic->{towner} ||= $username;
	$topic->{tverb} ||= 'is';
	$topic->{tstatus} ||= 'Online';
	$topic->{tdivider} ||= '|';
	$topic->{tstatic} ||= 'http://'.$self->{params}->{server};
	
	if ($cmd =~ /(topic|towner|tverb|tstatus|tdivider|tstatic)/) {
		$topic->{$cmd} = trim($value);
	}
	elsif ($cmd eq 'treset') {
		$self->irc_cmd( 'topic', nch($chan), ' ' );
		return "Topic for $chan has been cleared.";
	}
	elsif ($cmd eq 'ton') { $topic->{tstatus} = 'Online'; }
	elsif ($cmd eq 'toff') { $topic->{tstatus} = 'Offline'; }
	
	my $sep = ' ' . $topic->{tdivider} . ' ';
	my $topic_line = join( $sep, 
		$topic->{topic},
		$topic->{towner} . ' ' . $topic->{tverb} . ' ' . $topic->{tstatus},
		$topic->{tstatic}
	);
	
	$self->irc_cmd( 'topic', nch($chan), $topic_line );
	$self->dirty(1);
	
	# return "Topic for $chan has been updated.";
	return undef;
}

1;
