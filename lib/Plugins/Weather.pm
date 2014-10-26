package SimpleBot::Plugin::Weather;

##
# Weather.pm
# SimpleBot Plugin, reports the weather using WeatherUnderground.com or Yahoo!.
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
	
	if (!$self->{config}->{APIKey}) {
		if ($value =~ /^\d{5}$/) {
			# 5-digit US ZIP code, use Yahoo! (requires no API key).
			return $self->weather_yahoo($value, $args);
		}
		
		return "$username: No API key is set for WeatherUnderground.com.  Please type: !help weather";
	}
	
	$self->log_debug(9, "Forking for WeatherUnderground.com service...");
	
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		who => $args->{who_disp},
		run => sub {
			eval {
				my $response = '';
				my $metric = ($self->{config}->{Units} =~ /metric/i) ? 1 : 0;
				
				# resolve 'city state' or 'city country' to 'state_or_country/city_with_underscores'
				if ($value =~ s/\,?\s+(\S+)$//) {
					my $state_or_country = $1;
					$value = $state_or_country . '/' . $value;
					$value =~ s/\s+/_/g;
				}
				
				my $url = 'http://api.wunderground.com/api/'.$self->{config}->{APIKey}.'/conditions/q/'.$value.'.json';
				$self->log_debug(9, "Weather child fork, fetching: $url" );
				
				my $resp = wget( $url );
				if ($resp->is_success()) {
					my $weather = json_parse( $resp->content() );
					
					if ($args->{forecast}) {
						my $forecast_url = 'http://api.wunderground.com/api/'.$self->{config}->{APIKey}.'/forecast/q/'.$value.'.json';
						$self->log_debug(9, "Fetching forecast: $forecast_url" );
						
						$resp = wget( $forecast_url );
						if ($resp->is_success()) {
							my $forecast = json_parse( $resp->content() );
							if ($forecast) {
								$response = "Forecast for " . $weather->{current_observation}->{display_location}->{full} . ":\n";
								my $days = $forecast->{forecast}->{txt_forecast}->{forecastday};
								foreach my $day (@$days) {
									if ($day->{title} !~ /night/i) {
										$response .= $day->{title} . ": " . ($metric ? $day->{fcttext_metric} : $day->{fcttext}) . "\n";
									}
								}
							} # good json
						} # success
					} # forecast
					else {
						my $data = $weather->{current_observation};
						
						$response = "Current conditions for " . $data->{display_location}->{full} . ": ";
						$response .= $data->{weather};
						
						# $response .= ", " . $data->{temperature_string};
						if ($metric) { 
							# metric temp in C
							$response .= ", " . $data->{temp_c} . " C"; 
						}
						else { 
							# imperial temp in F
							$response .= ", " . $data->{temp_f} . " F"; 
						}
						
						# $response .= ", Wind: " . $data->{wind_string};
						$response .= ", Wind: ";
						if ($data->{wind_mph} >= 1.0) {
							$response .= "From the " . $data->{wind_dir} . " at ";
							if ($metric) {
								# metric wind in kph
								$response .= $data->{wind_kph} . " KPH Gusting to " . $data->{wind_gust_kph} . " KPH";
							}
							else {
								# imperial wind in mph
								$response .= $data->{wind_mph} . " MPH Gusting to " . $data->{wind_gust_mph} . " MPH";
							}
						}
						else {
							$response .= "Calm";
						} 
						
						$response .= ", Humidity: " . $data->{relative_humidity};
						
						# $response .= ", Pressure: " . $data->{pressure_in} . " in";
						$response .= ", Pressure: ";
						if ($metric) {
							# metric pressure in kPa
							my $kPa = $data->{pressure_mb} / 10;
							$response .= "$kPa kPa";
						}
						else {
							# imperial presusre in inches
							$response .= $data->{pressure_in} . " in";
						}
						if ($data->{pressure_trend} =~ /\+/) { $response .= " (Trending up)"; }
						elsif ($data->{pressure_trend} =~ /\-/) { $response .= " (Trending down)"; }
						
						$response .= ", Visibility: ";
						if ($metric) { $response .= $data->{visibility_km} . " KPH"; }
						else { $response .= $data->{visibility_mi} . " MPH"; }
						
						$response .= ", UV Index: " . $data->{UV} . "/12";
						
					} # conditions
					
					if ($response) {
						$self->log_debug(9, "Weather response: $response");
						print trim($response) . "\n";
					}
					elsif ($weather && $weather->{response} && $weather->{response}->{error} && $weather->{response}->{error}->{description}) {
						$response = "Weather Error: " . $weather->{response}->{error}->{description};
						$self->log_debug(9, "Weather response: $response");
						print trim($response) . "\n";
					}
					else { 
						$self->log_debug(9, "No response from weather API"); 
					}
					
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

sub weather_yahoo {
	# Get US weather using Yahoo and 5-digit US ZIP code
	# This is used as a fallback when there is no WeatherUnderground API Key
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
						$response = "Forecast for $nice_loc:\n";
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
