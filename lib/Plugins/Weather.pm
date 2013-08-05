package SimpleBot::Plugin::Weather;

##
# Weather.pm
# SimpleBot Plugin
# Copyright (c) 2013 Joseph Huckaby
# MIT Licensed
##

use strict;
use base qw( SimpleBot::Plugin );
use Tools;
use HTTP::Date;
use URI::Escape;
use DateTime;

sub init {
	my $self = shift;
	$self->register_commands('timezone', 'location', 'weather', 'forecast');
}

sub location {
	# set and remember location per user
	my ($self, $value, $args) = @_;
	my $username = $args->{who};
	
	if (!$value) { return "$username: You must specify your location for me to remember it."; }
	
	# user can set time zone independent of world weather location service
	my $tz_name = find_timezone_name( $value );
	if ($tz_name) {
		$self->log_debug(9, "Got timezone name: $tz_name (from: $value)");
		$self->{data}->{users} ||= {};
		my $user = $self->{data}->{users}->{lc($username)} ||= {};
		$user->{tz_name} = $tz_name;
		$self->dirty(1);
		
		my $dt = DateTime->from_epoch( epoch => time(), time_zone => $tz_name );
		my $tz_short_name = $dt->time_zone_short_name();
		return "$username: Okay, I'll remember your timezone '$tz_name' (currently $tz_short_name) for future queries.\n";
	}
	
	if (!$self->{config}->{APIKey}) {
		return "$username: No API key is set for WorldWeatherOnline.com (used for their location service).  Please type: !help weather";
	}
	
	$self->log_debug(9, "Forking for location service...");
	
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		who => $args->{who_disp},
		run => sub {
			eval {
				my $response = '';
				$value =~ s/\s+/,/g;
				my $url = 'http://api.worldweatheronline.com/free/v1/tz.ashx?q='.uri_escape($value).'&format=json&key=' . $self->{config}->{APIKey};
				$self->log_debug(9, "Location child fork, fetching: $url" );
				
				my $resp = wget( $url );
				if ($resp->is_success()) {
					my $json = json_parse( $resp->content() );
					my $data = $json->{data} || {};
					# { "data": { "request": [ {"query": "94403", "type": "Zipcode" } ],  "time_zone": [ {"localtime": "2013-07-06 11:36", "utcOffset": "-7.0" } ] }}
					if ($data->{time_zone} && $data->{time_zone}->[0] && $data->{time_zone}->[0]->{utcOffset}) {
						my $utc_offset = $data->{time_zone}->[0]->{utcOffset};
						my $nice_loc = ($data->{request} && $data->{request}->[0] && $data->{request}->[0]->{query}) ? $data->{request}->[0]->{query} : $value;
						
						$self->enqueue_plugin_task( 'update_user_loc', {
							username => $username,
							location => $value,
							nice_loc => $nice_loc,
							utc_offset => $utc_offset
						} );
						
						print "$username: Okay, I'll remember your location of $nice_loc for future queries.\n";
					}
					elsif ($data->{error} && $data->{error}->[0] && $data->{error}->[0]->{msg}) {
						$response = "Location Error: " . $data->{error}->[0]->{msg};
						$self->log_debug(9, "Location response: $response");
						print trim($response) . "\n";
					}
					else {
						print "$username: Unable to determine your location from: $value.  Please use: city, state/province, country.\n";
					}
				} # wget success
				else {
					die "Failed to fetch location data: $url: " . $resp->status_line() . "\n";
				}
			}; # eval
			if ($@) {
				my $error_msg = $@;
				$self->log_debug(2, "Location API Error: $error_msg");
				print "$username: Location API Error: $error_msg\n";
			}
		} # sub
	);
	
	return undef;
}
sub timezone { return location(@_); }

sub update_user_loc {
	# called from enqueue_plugin_task
	# update user location
	my ($self, $task) = @_;
	my $username = delete $task->{username};
	
	$self->{data}->{users} ||= {};
	my $user = $self->{data}->{users}->{lc($username)} ||= {};
	
	foreach my $key (keys %$task) {
		if ($key !~ /^(Command|Plugin|Type)$/) {
			$user->{$key} = $task->{$key};
		}
	}
	
	my $tz_name = find_timezone_name( $task->{utc_offset} );
	$user->{tz_name} = $tz_name || '';
	
	$self->log_debug(9, "Setting default weather location for $username: " . json_compose($user));
	
	$self->dirty(1);
	
	return 1;
}

sub weather {
	# get current conditions
	my ($self, $value, $args) = @_;
	my $username = $args->{who};
	
	if (!$value) {
		if ($self->{data}->{users}->{lc($username)}) { $value = $self->{data}->{users}->{lc($username)}->{location}; }
		else { return "$username: You didn't specify a location, and we don't have one on file for you."; }
	}
	
	if (!$self->{config}->{APIKey}) {
		return "$username: No API key is set for WorldWeatherOnline.com.  Please type: !help weather";
	}
	
	$self->log_debug(9, "Forking for weather service...");
	
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		who => $args->{who_disp},
		run => sub {
			eval {
				my $response = '';
				$value =~ s/\s+/,/g;
				my $url = 'http://api.worldweatheronline.com/free/v1/weather.ashx?q='.uri_escape($value).'&format=json&num_of_days=5&key=' . $self->{config}->{APIKey};
				$self->log_debug(9, "Weather child fork, fetching: $url" );
				
				my $resp = wget( $url );
				if ($resp->is_success()) {
					my $weather = json_parse( $resp->content() );
					if ($weather->{data}) {
						my $data = $weather->{data};
						if ($args->{forecast}) {
							# 5 day forecast
							if ($data->{weather} && ref($data->{weather})) {
								$response = "Forecast for " . $data->{request}->[0]->{query} . ":\n";
								foreach my $day (@{$data->{weather}}) {
									my $epoch = str2time( $day->{date} );
									$response .= get_nice_date($epoch) . ": " . $day->{weatherDesc}->[0]->{value};
									$response .= ", High: " . $day->{tempMaxC} . "C (" . $day->{tempMaxF} . "F)";
									$response .= ", Low: " . $day->{tempMinC} . "C (" . $day->{tempMinF} . "F)";
									if ($day->{windspeedMiles}) {
										$response .= ", Wind: " . $day->{winddir16Point} . " @ " . $day->{windspeedKmph} . " km/h (" . $day->{windspeedMiles} . " mph)";
									}
									else { $response .= ", Wind: None"; }
									$response .= "\n";
								} # foreach day
							} # good fmt
						} # forecast
						else {
							# current conditions
							my $cur = $data->{current_condition}->[0];
							if ($cur) {
								$response = "Current conditions for " . $data->{request}->[0]->{query} . ": ";
								$response .= $cur->{weatherDesc}->[0]->{value};
								$response .= ", " . $cur->{temp_C} . 'C (' . $cur->{temp_F} . 'F)';
								if ($cur->{windspeedMiles}) {
									$response .= ", Wind: " . $cur->{winddir16Point} . " @ " . $cur->{windspeedKmph} . " km/h (" . $cur->{windspeedMiles} . " mph)";
								}
								else { $response .= ", Wind: None"; }
								$response .= ", Humidity: " . $cur->{humidity} . '%';
							}
						} # current
						
						if ($response) {
							$self->log_debug(9, "Weather response: $response");
							print trim($response) . "\n";
						}
						elsif ($data && $data->{error} && $data->{error}->[0] && $data->{error}->[0]->{msg}) {
							$response = "Weather Error: " . $data->{error}->[0]->{msg};
							$self->log_debug(9, "Weather response: $response");
							print trim($response) . "\n";
						}
						else { $self->log_debug(9, "No response from weather API"); }
					} # json good
				} # wget success
				else {
					die "Failed to fetch weather: $url: " . $resp->status_line() . "\n";
				}
			}; # eval
			if ($@) {
				my $error_msg = $@;
				$self->log_debug(2, "Weather API Error: $error_msg");
				print "$username: Weather API Error: $error_msg\n";
			}
		} # sub
	);
	
	return undef;
}

sub forecast {
	# get 5 day forecast
	my ($self, $value, $args) = @_;
	
	$args->{forecast} = 1;
	return $self->weather($value, $args);
}

1;
