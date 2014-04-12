package SimpleBot::Plugin::Weather;

##
# Weather.pm
# SimpleBot Plugin, reports the weather using Yahoo! (US) or WorldWeatherOnline.com (Non-US).
# Copyright (c) 2013, 2014 Joseph Huckaby
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
	$self->register_commands('location', 'weather', 'forecast');
}

sub location {
	# set and remember location per user
	my ($self, $value, $args) = @_;
	my $username = $args->{who};
	
	if (!$value) { return "$username: You must specify your location for me to remember it."; }
	
	$self->{data}->{users} ||= {};
	my $user = $self->{data}->{users}->{lc($username)} ||= {};
	$user->{location} = $value;
	
	$self->log_debug(9, "Setting default weather location for $username: $value");
	$self->dirty(1);
	
	return "$username: Okay, I'll remember your location of $value for future weather queries.";
}

sub weather {
	# get current conditions
	my ($self, $value, $args) = @_;
	my $username = $args->{who};
	
	if (!$value) {
		if ($self->{data}->{users}->{lc($username)}) { $value = $self->{data}->{users}->{lc($username)}->{location}; }
		else { return "$username: You didn't specify a location, and we don't have one on file for you."; }
	}
	
	if ($value =~ /^\d{5}$/) {
		# 5-digit US ZIP code, use Yahoo! (It's more accurate and up to date than WWO for the US, and requires no API key).
		return $self->weather_yahoo($value, $args);
	}
	
	if (!$self->{config}->{APIKey}) {
		return "$username: No API key is set for WorldWeatherOnline.com.  Please type: !help weather";
	}
	
	$self->log_debug(9, "Forking for WorldWeatherOnline.com service...");
	
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
									my $nice_date = get_nice_date( $epoch, 0, 1 ); $nice_date =~ s/\,\s+\d{4}$//;
									$response .= $nice_date . ": " . $day->{weatherDesc}->[0]->{value};
									
									$response .= ", High: " . $self->getFormattedTemperature(
										C => $day->{tempMaxC} . 'C',
										F => $day->{tempMaxF} . 'F'
									);
									$response .= ", Low: " . $self->getFormattedTemperature(
										C => $day->{tempMinC} . 'C',
										F => $day->{tempMinF} . 'F'
									);
									
									# $response .= ", High: " . $day->{tempMaxC} . "C (" . $day->{tempMaxF} . "F)";
									# $response .= ", Low: " . $day->{tempMinC} . "C (" . $day->{tempMinF} . "F)";
									
									if ($day->{windspeedMiles}) {
										$response .= ", Wind: " . $day->{winddir16Point} . " @ " . $self->getFormattedSpeed(
											K => $day->{windspeedKmph} . ' km/h',
											M => $day->{windspeedMiles} . ' mph'
										);
										
										# $response .= ", Wind: " . $day->{winddir16Point} . " @ " . $day->{windspeedKmph} . " km/h (" . $day->{windspeedMiles} . " mph)";
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
								
								$response .= ", " . $self->getFormattedTemperature(
									C => $cur->{temp_C} . 'C',
									F => $cur->{temp_F} . 'F'
								);
								# $response .= ", " . $cur->{temp_C} . 'C (' . $cur->{temp_F} . 'F)';
								
								if ($cur->{windspeedMiles}) {
									$response .= ", Wind: " . $cur->{winddir16Point} . " @ " . $self->getFormattedSpeed(
										K => $cur->{windspeedKmph} . ' km/h',
										M => $cur->{windspeedMiles} . ' mph'
									);
									# $response .= ", Wind: " . $cur->{winddir16Point} . " @ " . $cur->{windspeedKmph} . " km/h (" . $cur->{windspeedMiles} . " mph)";
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

sub getFormattedTemperature {
	# format temperature based on config string
	my $self = shift;
	my $args = {@_};
	my $template = $self->{config}->{DegreeUnits};
	$template =~ s/(\w+)/ $args->{$1} || ''; /eg;
	return $template;
}

sub getFormattedSpeed {
	# format speed based on config string
	my $self = shift;
	my $args = {@_};
	my $template = $self->{config}->{WindSpeedUnits};
	$template =~ s/(\w+)/ $args->{$1} || ''; /eg;
	return $template;
}

sub weather_yahoo {
	# Get US weather using Yahoo and 5-digit US ZIP code
	my ($self, $value, $args) = @_;
	my $username = $args->{who};
	
	# http://weather.yahooapis.com/forecastrss?p=94403&u=f
	
	$self->log_debug(9, "Forking for Yahoo weather service...");
	
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		who => $args->{who_disp},
		run => sub {
			eval {
				my $response = '';
				$value =~ s/\s+/,/g;
				my $url = 'http://weather.yahooapis.com/forecastrss?p='.uri_escape($value).'&u=f';
				$self->log_debug(9, "Weather child fork, fetching: $url" );
				
				my $resp = wget( $url );
				if ($resp->is_success()) {
					my $xml = parse_xml( $resp->content() );
					if (!ref($xml)) {
						die "Failed to parse XML from weather service: $url: $xml\n";
					}
					if (!$xml->{channel} || !$xml->{channel}->{item} || !$xml->{channel}->{item}->{'yweather:condition'}) {
						die "Malformed XML from weather service: $url\n";
					}
					my $channel = $xml->{channel};
					my $item = $channel->{item};
					
					my $nice_loc = $value;
					# <yweather:location city="San Mateo" region="CA" country="US"/>
					if ($channel->{'yweather:location'}) {
						my $loc = $channel->{'yweather:location'};
						$nice_loc = $loc->{city} . ", " . $loc->{region} . ", " . $loc->{country};
					}
					elsif ($item->{title} =~ /Conditions\s+for\s+(.+?)\s+at\s+/) { $nice_loc = $1; }
					
					my $units = $channel->{'yweather:units'} || { temperature=>"F", distance=>"mi", pressure=>"in", speed=>"mph" };
					foreach my $key (keys %$units) {
						$units->{$key} = ' ' . $units->{$key};
					}
					
					if ($args->{forecast}) {
						# <yweather:forecast day="Sat" date="12 Apr 2014" low="57" high="74" text="Partly Cloudy" code="30"/>
						foreach my $fore (@{$item->{'yweather:forecast'}}) {
							my $epoch = str2time( $fore->{date} );
							my $nice_date = get_nice_date( $epoch, 0, 1 ); $nice_date =~ s/\,\s+\d{4}$//;
							$response .= "$nice_date: " . $fore->{text};
							$response .= ", High: " . $fore->{high} . $units->{temperature};
							$response .= ", Low: " . $fore->{low} . $units->{temperature};
							$response .= "\n";
						}
					} # forecast
					else {
						$response = "Current conditions for $nice_loc: ";
						$response .= $item->{'yweather:condition'}->{text} . ", ";
						$response .= $item->{'yweather:condition'}->{temp} . $units->{temperature};
						
						if ($item->{'yweather:forecast'} && $item->{'yweather:forecast'}->[0]) {
							my $fore = $item->{'yweather:forecast'}->[0];
							$response .= " (High: " . $fore->{high} . $units->{temperature} . ", Low: " . $fore->{low} . $units->{temperature} . ")";
						}
						
						if ($channel->{'yweather:wind'}) {
							$response .= ", Wind: " . $channel->{'yweather:wind'}->{speed} . $units->{speed};
						}
						
						if ($channel->{'yweather:atmosphere'}) {
							my $atmos = $channel->{'yweather:atmosphere'};
							$response .= ", Humidity: " . $atmos->{humidity} . "%";
							$response .= ", Pressure: " . $atmos->{pressure} . $units->{pressure};
							$response .= ", Visibility: " . $atmos->{visibility} . $units->{distance};
						}
					} # current conditions
					
					$self->log_debug(9, "Weather response: $response");
					print trim($response) . "\n";
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

1;
