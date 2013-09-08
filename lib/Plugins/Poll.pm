package SimpleBot::Plugin::Poll;

##
# Poll.pm
# SimpleBot Plugin
# Copyright (c) 2013 Joseph Huckaby
# MIT Licensed
#
# !poll (status)
# !poll open What's your favorite color?
# !poll close
# !poll results
# !vote blue
##

use strict;
use base qw( SimpleBot::Plugin );
use Tools;

sub init {
	my $self = shift;
	$self->register_commands('poll', 'vote');
}

sub poll {
	# manage polls
	my ($self, $cmd, $args) = @_;
	my $username = $args->{who};
	my $chan = $args->{channel};
	
	if ($chan eq 'msg') {
		return "You can only use polls in a #channel.";
	}
	
	if (!$self->{data}->{channels}) { $self->{data}->{channels} = {}; }
	my $poll = $self->{data}->{channels}->{ sch(lc($chan)) } ||= {};
	
	if (!$cmd || ($cmd =~ /^status$/i)) {
		# get poll status
		if ($poll->{open}) { return "$username: Poll is currently open for votes: " . $poll->{title} . " (started by " . $poll->{username} . ")"; }
		else { return "$username: There is no poll currently open."; }
	}
	elsif ($cmd =~ /^(open|create|add|start|new)(.*)$/i) {
		# open a new poll
		my $title = trim($2);
		if ($poll->{open}) { return "$username: There is a poll already open: " . $poll->{title} . ".  To close this poll, type !poll close"; }
		
		$poll->{votes} = {};
		$poll->{display_titles} = {};
		
		if ($title =~ s/\s*\((.+)\)\s*$//) {
			# limit poll to a specific set of valid vote choices
			my $values_raw = $1;
			$poll->{limit_votes} = 1;
			
			foreach my $value (split(/\,\s*/, $values_raw)) {
				$value = trim($value);
				if ($value =~ /\S/) {
					$poll->{votes}->{lc($value)} = 0;
					$poll->{display_titles}->{lc($value)} = $value;
				}
			}
			
			if (scalar keys %{$poll->{votes}} < 2) {
				return "$username: You didn't supply enough valid vote choices.  See '!help poll' for details.";
			}
		}
		else {
			# open ended poll, users can type anything
			$poll->{limit_votes} = 0;
		}
		
		if (!$title) { return "$username: You need to specify a topic for your poll."; }
		
		if ($poll->{total_votes}) { $self->archive_poll($poll); }
		
		$self->log_debug(8, "New poll opened by $username: $title");
		
		$poll->{open} = 1;
		$poll->{date} = time();
		$poll->{username} = $username;
		$poll->{channel} = $chan;
		$poll->{title} = $title;
		$poll->{users} = {};
		$poll->{total_votes} = 0;
		$self->dirty(1);
		
		my $response = "";
		$response .= "$username has started a new poll: \"$title\".  Please use the '!vote' command to cast your vote";
		if ($poll->{limit_votes}) {
			$response .= " for one of the following choices: " . get_english_list( [sort values %{$poll->{display_titles}}], 'or' );
		}
		else {
			$response .= "!";
		}
		
		$self->say( channel => nch($chan), body => $response );
	}
	elsif ($cmd =~ /^close/i) {
		# close a poll
		if (!$poll->{open}) { return "$username: There is no poll currently open."; }
		
		$poll->{open} = 0;
		$self->dirty(1);
		
		$self->say( channel => nch($chan), body => "The poll is now closed.  Thanks for your votes!" );
	}
	elsif ($cmd =~ /^results/i) {
		# get poll results
		if (!$poll->{title}) { return "$username: There have been no recent polls."; }
		if (!$poll->{total_votes}) { return "$username: No users have cast any votes yet."; }
		
		my $body = "Poll Results: " . $poll->{title} . "\n";
		foreach my $vote_id (reverse sort { $poll->{votes}->{$a} <=> $poll->{votes}->{$b} } keys %{$poll->{votes}}) {
			$body .= $poll->{display_titles}->{$vote_id} . ": ";
			$body .= commify($poll->{votes}->{$vote_id}) . " ".pluralize("vote", $poll->{votes}->{$vote_id})." ";
			$body .= "(" . pct($poll->{votes}->{$vote_id}, $poll->{total_votes}) . ")\n";
		}
		$self->say( channel => nch($chan), body => $body );
	}
	elsif ($cmd =~ /^history/i) {
		# show recent closed poll history
		my $archives = [];
		if ($self->{data}->{archives} && @{$self->{data}->{archives}}) { push @$archives, @{$self->{data}->{archives}}; }
		my $body = "Recent Poll Results:\n";
		my $count = 0;
		if ($poll->{total_votes} && !$poll->{open}) {
			unshift @$archives, $poll;
		}
		if (!@$archives) { return "$username: There have been no recent polls."; }
		
		foreach my $archive (@$archives) {
			if ($archive->{channel} eq $chan) {
				$body .= yyyy_mm_dd($archive->{date}) . ": " . $archive->{title} . ": ";
				my $idx = 0;
				foreach my $vote_id (reverse sort { $archive->{votes}->{$a} <=> $archive->{votes}->{$b} } keys %{$archive->{votes}}) {
					if ($idx) { $body .= ', '; }
					$body .= $archive->{display_titles}->{$vote_id} . " (";
					$body .= commify($archive->{votes}->{$vote_id}) . " - ";
					$body .= pct($archive->{votes}->{$vote_id}, $archive->{total_votes}) . ")";
					$idx++;
				}
				$body .= "\n";
				$count++;
			}
		}
		if (!$count) { return "$username: There have been no recent polls for this channel."; }
		$self->say( channel => nch($chan), body => $body );
	}
	elsif ($cmd =~ /^delete/i) {
		# delete current poll
		delete $self->{data}->{channels}->{ sch(lc($chan)) };
		$self->dirty(1);
		return "$username: Okay, all current poll data deleted (history is preserved).";
	}
	else {
		return "$username: Sorry, I do not understand that poll command.  If you are trying to start a new poll, use: !poll open YOUR TITLE HERE";
	}
	
	return undef;
}

sub vote {
	# vote for an open poll
	my ($self, $value, $args) = @_;
	
	my $username = $args->{who};
	my $chan = $args->{channel};
	my $vote_id = lc($value);
	
	if ($chan eq 'msg') {
		return "You can only vote in a channel with an open poll.";
	}
	
	if (!$self->{data}->{channels}) { $self->{data}->{channels} = {}; }
	my $poll = $self->{data}->{channels}->{ sch(lc($chan)) } ||= {};
	
	if (!length($value)) {
		return "$username: You need to specify a value for your vote.";
	}
	if (!$poll->{open}) {
		return "$username: There is no poll currently open.";
	}
	if ($poll->{users}->{lc($username)}) {
		return "$username: Sorry, you have already cast your vote.";
	}
	
	# poll can limit to a specific set of predefined choices
	if ($poll->{limit_votes} && !defined($poll->{votes}->{$vote_id})) {
		return "$username: Sorry, you need to vote for one of the following choices: " . get_english_list( [sort values %{$poll->{display_titles}}], 'or' );
	}
	
	$self->log_debug(9, "User $username voted for: $value");
	
	# cast vote
	$poll->{votes}->{$vote_id}++;
	$poll->{total_votes}++;
	$poll->{display_titles}->{$vote_id} ||= $value;
	$poll->{users}->{lc($username)} = 1;
	$self->dirty(1);
	
	return "$username: Thank you for your vote!";
}

sub nick_change {
	# called when a user nick changes
	my ($self, $args) = @_;
	
	if ($self->{data}->{channels}) {
		foreach my $chan (keys %{$self->{data}->{channels}}) {
			my $poll = $self->{data}->{channels}->{$chan};
			if ($poll->{users}->{ lc($args->{old_nick}) }) {
				delete $poll->{users}->{ lc($args->{old_nick}) };
				$poll->{users}->{ lc($args->{new_nick}) } = 1;
				$self->dirty(1);
			} # user voted using old nick
		} # foreach channel
	} # has channel data
}

sub archive_poll {
	# archive poll results for later
	my ($self, $poll) = @_;
	$poll = deep_copy($poll);
	
	my $archives = $self->{data}->{archives} ||= [];
	if (scalar @$archives > 10) { pop @$archives; }
	
	delete $poll->{users};
	
	unshift @$archives, $poll;
	$self->dirty(1);
}

1;
