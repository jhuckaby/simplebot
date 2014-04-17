package SimpleBot::Plugin::Earthquake;

##
# Earthquake.pm
# SimpleBot Plugin
# Provides earthquake notifications from the USGS feeds
#
# !quakes on
# !quakes off
# !quake
##

use strict;
use base qw( SimpleBot::Plugin );
use Tools;

sub init {
	my $self = shift;
	$self->register_commands('quakes');
	
	if ($self->{data}->{monitor_enabled}) {
		$self->prime_quakes();
	}
}

sub config_changed {
	# called automatically when configuration changes
	# i.e. owner is setting the feed id
	my $self = shift;
	$self->init();
}

sub quakes {
	# quake commands
	my ($self, $msg, $args) = @_;
	my $username = $args->{who};
	my $chan = $args->{channel};
	
	if ($msg =~ /^on/i) {
		# enable quakes in current channel
		$self->{data}->{monitor_enabled} = 1;
		$self->{data}->{channel} = nch($chan);
		$self->prime_quakes();
		$self->dirty(1);
		return "Earthquake monitoring enabled in $chan.";
	}
	elsif ($msg =~ /^off/i) {
		# disable quake monitoring
		$self->{data}->{monitor_enabled} = 0;
		$self->dirty(1);
		return "Earthquake monitoring disabled.";
	}
	elsif ($msg =~ /^status/i) {
		# show status, channel
		if ($self->{data}->{monitor_enabled}) {
			return "Earthquake monitoring is currently enabled in channel ".nch($self->{data}->{channel})." (category: ".$self->{config}->{FeedID}.").";
		}
		else {
			return "Earthquake monitoring is disabled.";
		}
	}
	else {
		# emit most recent quake, even if repeat
		my $quakes = $self->get_quakes('day');
		if (@$quakes) {
			my $quake = $quakes->[0];
			my $props = $quake->{properties};
			my $nice_date = get_nice_date( $props->{'time'} / 1000, 1, 1, 1 );
			return "Most recent earthquake: $nice_date: Magnitude " . $props->{mag} . ", " . $props->{place} . ": " . $props->{url};
		}
		else {
			return "No quakes found in the last 24 hours (category: " . $self->{config}->{FeedID} . ")";
		}
	}
}

sub tick {
	# monitor USGS API for new earthquakes
	my $self = shift;
	my $now = time();
	
	if (!$self->{data}->{monitor_enabled} || !$self->{data}->{channel}) { return; }
	
	if (!$self->{last_quake_check} || (($now - $self->{last_quake_check}) >= $self->{config}->{APIPingFreq})) {
		$self->{last_quake_check} = $now;
		
		$self->log_debug(9, "Forking to check USGS earthquakes");
		
		$self->{bot}->forkit(
			channel => nch( $self->{data}->{channel} ),
			handler => '_fork_utf8_said',
			run => sub {
				eval {
					my $quakes = $self->get_quakes();
					my $add_ids = {};
					my $remove_ids = {};
					my $num_actions = 0;
					my $num_new_quakes = 0;
					
					foreach my $quake (@$quakes) {
						if (!$self->{data}->{quakes}->{ $quake->{id} }) {
							# new quake!!!
							$add_ids->{ $quake->{id} } = 1;
							$num_actions++;
							$num_new_quakes++;
							my $props = $quake->{properties};
							$self->log_debug(9, "New quake detected: " . $quake->{id} . ": " . json_compose($props));
							print "New Earthquake: Magnitude " . $props->{mag} . ", " . $props->{place} . ": " . $props->{url} . "\n";
						}
					}
					foreach my $quake_id (keys %{$self->{data}->{quakes}}) {
						if (!find_object($quakes, { id => $quake_id })) {
							# quake has fallen off the feed
							$remove_ids->{$quake_id} = 1;
							$num_actions++;
							$self->log_debug(9, "Earthquake disappeared from feed: $quake_id");
						}
					}
					
					if ($num_actions) {
						$self->enqueue_plugin_task( 'update_quake_ids', {
							add => $add_ids,
							remove => $remove_ids
						} );
					}
					
					if (!$num_new_quakes) {
						print "\n"; # child forks always need to print something
					}
				}; # eval
				if ($@) { print "Earthquake Error: $@\n"; }
			} # sub
		); # fork
		
	} # time to ping
}

sub update_quake_ids {
	# update quake ids in data -- called by child fork via enqueue_plugin_task()
	my ($self, $args) = @_;
	
	$self->log_debug(9, "Updating quake data from fork: " . json_compose($args));
		
	foreach my $quake_id (keys %{$args->{add}}) {
		$self->{data}->{quakes}->{$quake_id} = 1;
	}
	foreach my $quake_id (keys %{$args->{remove}}) {
		delete $self->{data}->{quakes}->{$quake_id};
	}
	
	$self->dirty(1);
}

sub prime_quakes {
	# prime quake data, so we don't repeat recent quakes at startup
	# also, prune old data no longer in feed
	my $self = shift;
	$self->{data}->{quakes} ||= {};
	
	my $quakes = $self->get_quakes();
	
	foreach my $quake (@$quakes) {
		$self->{data}->{quakes}->{ $quake->{id} } = 1;
	}
	foreach my $quake_id (keys %{$self->{data}->{quakes}}) {
		if (!find_object($quakes, { id => $quake_id })) {
			delete $self->{data}->{quakes}->{$quake_id};
		}
	}
}

sub get_quakes {
	# get all recent quakes from usgs hourly feeds
	# return as array ref
	my $self = shift;
	my $range = shift || 'hour';
	my $quakes = [];
	
	my $quake_feed_id = $self->{config}->{FeedID};
	my $url = 'http://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/'.$quake_feed_id.'_'.$range.'.geojson';
	$self->log_debug(9, "Fetching USGS earthquake data: $url");
	
	my $json_raw = trim(file_get_contents($url));
	$self->log_debug(9, "Raw result: $json_raw");
	
	my $json = eval { json_parse( $json_raw ); };
	if ($json && $json->{features} && $json->{features}->[0]) {
		foreach my $event (@{$json->{features}}) {
			if ($event->{properties} && $event->{properties}->{type} && ($event->{properties}->{type} eq 'earthquake')) {
				push @$quakes, $event;
			}
		}
	}
	
	return $quakes;
}

1;
