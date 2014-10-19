package SimpleBot::Plugin::Twitter;

##
# Twitter.pm
# SimpleBot Plugin
# Copyright (c) 2013 Joseph Huckaby
# MIT Licensed
##

use strict;
use base qw( SimpleBot::Plugin );
use Tools;
use Net::Twitter::Lite::WithAPIv1_1;
use Encode qw(decode encode);

sub init {
	my $self = shift;
	
	$self->register_commands('rt', 'follow', 'unfollow', 'following', 'followers', 'twitter');
	
	# only init if we have the proper api keys set
	foreach my $key ('ConsumerKey', 'ConsumerSecret', 'AccessToken', 'AccessTokenSecret') {
		if (!$self->{config}->{$key}) { return; }
	}
	
	local $SIG{'__DIE__'} = undef;
	
	$self->{twitter} = Net::Twitter::Lite::WithAPIv1_1->new(
		ssl => 1,
		consumer_key        => $self->{config}->{ConsumerKey},
		consumer_secret     => $self->{config}->{ConsumerSecret},
		access_token        => $self->{config}->{AccessToken},
		access_token_secret => $self->{config}->{AccessTokenSecret}
	);
	
	$self->{data}->{follow} ||= {};
	
	# prime user data, so we don't keep RTing their last tweet on startup
	foreach my $username (keys %{$self->{data}->{follow}}) {
		my $tweet = $self->get_last_tweet($username);
		if ($tweet) {
			$self->log_debug(9, "Registered initial tweet ID for $username: " . $tweet->{id});
			$self->{data}->{follow}->{$username}->{last_tweet_id} = $tweet->{id};
		}
	} # foreach user
}

sub config_changed {
	# called automatically when configuration changes
	# i.e. owner is setting up our api keys
	my $self = shift;
	$self->init();
}

sub twitter {
	# umbrella command for all the other commands
	my ($self, $cmd, $args) = @_;
	my $username = $args->{who};
	
	if (!$self->{twitter}) {
		return "$username: ERROR: Twitter Plugin is not configured.  Please type: !help twitter";
	}
	
	if ($cmd =~ /^(\w+)(.*)$/) {
		my ($sub_cmd, $value) = ($1, $2);
		$value = trim($value);
		if ($self->can($sub_cmd)) { return $self->$sub_cmd($value, $args); }
		else { return "$username: Unknown Twitter command: $sub_cmd"; }
	}
	
	return undef;
}

sub reload {
	# reinit twitter api connection
	my ($self, $cmd, $args) = @_;
	my $username = $args->{who};
	
	$self->init();
	
	return "$username: Twitter API has been reloaded.";
}

sub rt {
	# retweet someone
	my ($self, $username, $args) = @_;
	$username = ntu($username);
	
	if (!$self->{twitter}) {
		return "ERROR: Twitter Plugin is not configured.  Please type: !help twitter";
	}
	
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		who => $args->{who_disp},
		handler => '_fork_utf8_said',
		run => sub {
			eval {
				my $tweet = $self->get_last_tweet($username);
				if ($tweet) {
					$self->log_debug(9, "Retweeting: $username: " . $tweet->{text});
					print 'RT @' . $username . " " . encode('UTF-8', $tweet->{text}, Encode::FB_QUIET) . "\n"; 
				}
				else { print "Could not get latest tweet for \@$username.\n"; }
			}; # eval
			if ($@) { print "Twitter Error: $@\n"; }
		} # sub
	);
	
	return undef;
}

sub follow {
	# follow someone into current channel
	my ($self, $username, $args) = @_;
	$username = ntu($username);
	my $channel = sch($args->{channel});
	
	if (!$self->{twitter}) {
		return "ERROR: Twitter Plugin is not configured.  Please type: !help twitter";
	}
	if ($channel eq 'msg') {
		return "Twitter: Cannot follow someone in a private message channel.  Please issue command in a real #channel.";
	}
	
	$self->{data}->{follow}->{$username} ||= {};
	$self->{data}->{follow}->{$username}->{channel} ||= '';
	
	if ($self->{data}->{follow}->{$username}->{channel} eq $channel) {
		return "Twitter: Already following \@".$username." in \#".$channel.".";
	}
	
	# store last tweet id, so we only RT his/her NEXT tweet
	my $tweet = $self->get_last_tweet($username);
	if (!$tweet) {
		delete $self->{data}->{follow}->{$username};
		return "Twitter Error: Cannot access user \@".$username."'s timeline.";
	}
	$self->{data}->{follow}->{$username}->{last_tweet_id} = $tweet->{id};
	$self->{data}->{follow}->{$username}->{channel} = $channel;
	$self->dirty(1);
	
	$self->log_debug(9, "Now following $username in $channel");
	$self->log_debug(9, "Last Tweet: " . $tweet->{id} . ": " . $tweet->{text});
	
	return "Twitter: Now following \@".$username." (in \#".$channel.").";
}

sub unfollow {
	# unfollow someone from current channel
	my ($self, $username, $args) = @_;
	$username = ntu($username);
	
	if (!$self->{twitter}) {
		return "ERROR: Twitter Plugin is not configured.  Please type: !help twitter";
	}
	
	if ($self->{data}->{follow}->{$username}) {
		delete $self->{data}->{follow}->{$username};
		$self->dirty(1);
		return "Twitter: No longer following \@".$username.".";
	}
	else {
		return "Twitter: We're not following \@".$username.".";
	}
}

sub following {
	# list all followers
	my ($self, $value, $args) = @_;
	
	if (!$self->{twitter}) {
		return "ERROR: Twitter Plugin is not configured.  Please type: !help twitter";
	}

	my $users = [ sort keys %{$self->{data}->{follow}} ];
	if (scalar @$users) {
		my $strs = [];
		foreach my $username (@$users) {
			my $channel = $self->{data}->{follow}->{$username}->{channel};
			push @$strs, "\@" . $username . " (in \#" . $channel . ")";
		}
		return "Twitter: Currently following: " . join(', ', @$strs); 
	}
	else { return "Twitter: Not following anyone at the moment."; }
}
sub followers { my $self = shift; return $self->following(@_); }

sub tick {
	# monitor twitter API for changes to our followees
	my $self = shift;
	my $now = time();
	
	if (!$self->{twitter}) { return; }
	
	if (!$self->{last_twitter_check} || (($now - $self->{last_twitter_check}) >= $self->{config}->{APIPingFreq})) {
		$self->{last_twitter_check} = $now;
		
		if (!$self->{user_ping_list} || !(scalar @{$self->{user_ping_list}})) {
			$self->{user_ping_list} = [ keys %{$self->{data}->{follow}} ];
		}
		my $username = shift @{$self->{user_ping_list}};
		if ($username && $self->{data}->{follow}->{$username}) {
			
			$self->log_debug(9, "Forking to check tweets for $username (last tweet id: " . $self->{data}->{follow}->{$username}->{last_tweet_id} . ")");
			
			$self->{bot}->forkit(
				channel => nch( $self->{data}->{follow}->{$username}->{channel} ),
				handler => '_fork_utf8_said',
				run => sub {
					eval {
						my $tweet = $self->get_last_tweet($username);
						if ($tweet) { $self->log_debug(9, "Got tweet: " . $tweet->{id} . ": " . $tweet->{text}); }
						
						if ($tweet && ($tweet->{id} ne $self->{data}->{follow}->{$username}->{last_tweet_id})) {
							# new tweet for user!
							$self->enqueue_plugin_task( 'update_tweet_id', {
								username => $username,
								new_tweet_id => $tweet->{id}
							} );
							print 'RT @' . $username . " " . encode('UTF-8', $tweet->{text}, Encode::FB_QUIET) . "\n";
						} # new tweet!
						else {
							print "\n"; # child forks always need to print something	
						}
					}; # eval
					if ($@) { print "Twitter Error: $@\n"; }
				} # sub
			); # fork
			
		} # good user
	} # time to ping
}

sub update_tweet_id {
	# update tweeet id in data -- called by child fork via enqueue_plugin_task()
	my ($self, $args) = @_;
	
	my $username = $args->{username};
	my $tweet_id = $args->{new_tweet_id};
	
	if ($self->{data}->{follow}->{$username}) {
		$self->log_debug(9, "Updating tweet ID for user $username: $tweet_id");
		
		$self->{data}->{follow}->{$username}->{last_tweet_id} = $tweet_id;
		$self->dirty(1);
	}
}

sub ntu {
	# ntu = normalize twitter username
	my $username = lc(shift @_);
	$username =~ s/^\@//;
	return $username;
}

sub get_last_tweet {
	# get last tweet for specified username
	my ($self, $username) = @_;
	$username = ntu($username);
	
	my $result = undef;
	eval {
		$result = $self->{twitter}->user_timeline({
			user_id => $username,
			screen_name => $username,
			count => 1,
			exclude_replies => 1,
			include_rts => 0
		});
	};
	if ($@) {
		$self->log_debug(4, "Twitter API Fail: $username: $@");
		return undef;
	}

	# use Data::Dumper;
	# print Dumper $result;
	# exit;
	
	if ($result && ref($result) && (scalar @$result)) {
		my $tweet = shift @$result;
		# $tweet->{text} =~ s@([\x01-\x08\x0B-\x0C\x0E-\x1F\x80-\xFF])@@g;
		# $tweet->{text} = encode('UTF-8', $tweet->{text}, Encode::FB_QUIET);
		$tweet->{text} = decode_entities($tweet->{text});
		
		# Resolve shortened URLs, i.e. http://t.co/N53Psnbi1S
		$tweet->{text} =~ s@(\w+\:\/\/t\.co\/\w+)@ follow_url_redirects($1); @eg;
		
		return $tweet;
	}
	
	return undef;
}

sub follow_url_redirects {
	# follow url redirect and return final URL
	my $url = shift;
	my $done = 0;
	my $count = 0;
	
	while (!$done) {
		my $ua = LWP::UserAgent->new( max_redirect => 0 );
		my $resp = $ua->request( HTTP::Request->new( 'HEAD', $url ) );
		my $code = $resp->code();
		if (($code =~ /3\d\d/) && $resp->header('Location')) {
			$url = $resp->header('Location');
			$count++; if ($count > 2) { $done = 1; }
		}
		else { $done = 1; }
	}
	
	return $url;
}

1;
