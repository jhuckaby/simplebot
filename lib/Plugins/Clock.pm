package SimpleBot::Plugin::Clock;

##
# Clock.pm
# SimpleBot Plugin
# Clock, alarms, countdown, reminders.
#
# !clock
# !clock TIMEZONE
#
# !alarm set 8:30 pm
# !alarm list
# !alarm delete all
#
# !countdown to 8:30 pm
# !countdown to calendar
# !countdown stop
# 
# !timer 5:00
# !timer stop
#
# !timezone Pacific
# !timezone Eastern
# !timezone America/Los_Angeles
# !timezone GMT-0800
##

use strict;
use base qw( SimpleBot::Plugin );
use Tools;
use DateTime;
use DateTime::TimeZone;

my $wday_map = { sun => 0, mon => 1, tue => 2, wed => 3, thu => 4, fri => 5, sat => 6 };
my $wday_re = "(sunday|sun|monday|mon|tuesday|tues?|wednesday|wed|thursday|thu|thur|thurs|friday|fri|saturday|sat|sunday|sun)";

my $month_map = {
	jan => 1, feb => 2, mar => 3, apr => 4, may => 5, jun => 6,
	jul => 7, aug => 8, sep => 9, oct => 10, nov => 11, dec => 12
};
my $month_re = "(january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept?|october|oct|november|nov|december|dec)";

sub init {
	my $self = shift;
	$self->register_commands('clock', 'time', 'alarm', 'countdown', 'timer', 'timezone');
	
	# cache local timezone for later use
	$self->{local_tz} = DateTime::TimeZone->new( name => 'local' );
}

sub handler {
	# generic handler to catch 'time' and 'alarm', so we don't have to redefine perl built-in funcs
	my ($self, $cmd, $value, $args) = @_;
	if ($cmd =~ /time/i) { return $self->clock($value, $args); }
	elsif ($cmd =~ /alarm/i) { return $self->alarm($value, $args); }
}

sub timezone {
	# set user's timezone for date/time related queries
	my ($self, $value, $args) = @_;
	my $username = $args->{who};
	
	if (!$value) { return "$username: You must specify your timezone for me to remember it."; }
	
	my $tz_name = find_timezone_name( $value );
	if ($tz_name) {
		$self->log_debug(9, "Got timezone name: $tz_name (from: $value)");
		$self->{data}->{users} ||= {};
		my $user = $self->{data}->{users}->{lc($username)} ||= {};
		$user->{tz_name} = $tz_name;
		$self->dirty(1);
		
		my $dt = DateTime->from_epoch( epoch => time(), time_zone => $tz_name );
		my $tz_short_name = $dt->time_zone_short_name();
		return "$username: Okay, I'll remember your timezone '$tz_name' (currently $tz_short_name) for future date/time queries.\n";
	}
	else {
		return "$username: Could not determine timezone.  Please type !help timezone.\n";
	}
}

sub clock {
	# show the current date/time in the user's timezone
	my ($self, $value, $args) = @_;
	my $username = $args->{who};
	my $chan = nch($args->{channel});
	
	# see if we have a timezone on file for user
	my $tz_name = 'local';
	if ($value =~ /\S/) {
		$tz_name = find_timezone_name($value) || 'local';
	}
	else {
		$tz_name = $self->get_user_timezone($username) || 'local';
	}
	
	my $dt = DateTime->from_epoch( epoch => time(), time_zone => $tz_name );
	return "It is currently " . normalize_space($dt->strftime("%A, %e %B %Y")) . " at " . trim($dt->strftime("%l:%M:%S %p %Z"));
}

sub timer {
	# countdown timer, specify duration instead of absolute date/time
	my ($self, $value, $args) = @_;
	my $username = $args->{who};
	my $chan = nch($args->{channel});
	
	$self->{data}->{channels} ||= {};
	my $channel_data = $self->{data}->{channels}->{sch($chan)} ||= {};
	my $countdown = $channel_data->{countdown} ||= {};
	
	if ($value =~ /\S/) {
		# start new countdown
		my $raw = $value;
		
		if ($raw =~ /^(stop|cancel|abort|off)/i) {
			# cancel countdown
			if (!$countdown->{active}) {
				return "$username: There is no timer currently active in $chan.";
			}
			$countdown->{active} = 0;
			delete $channel_data->{countdown};
			$self->dirty(1);
			
			return "$username: Timer has been cancelled.";
		}
		else {
			# start timer
			my $now = time();
			my $tz_name = $self->get_user_timezone($username) || 'local';
			# if (!$tz_name) { return "$username: Cannot use timers until you set your timezone.  Try !help timezone"; }
			
			my $prev_user = '';
			if ($countdown->{active}) {
				$prev_user = $countdown->{username};
			}
			
			my $duration = 0;
			if ($raw =~ /(\d+)\:(\d+)\:(\d+)/) {
				# hh:mm:ss
				my ($hh, $mm, $ss) = ($1, $2, $3);
				$duration = ($hh * 3600) + ($mm * 60) + $ss;
			}
			elsif ($raw =~ /(\d+)\:(\d+)/) {
				# mm:ss
				my ($mm, $ss) = ($1, $2);
				$duration = ($mm * 60) + $ss;
			}
			else {
				$duration = get_seconds_from_text($raw);
			}
			
			if (!$duration) { return "$username: Unable to determine timer duration.  Try !timer MM::SS or !timer HH::MM::SS"; }
			
			$countdown->{duration} = $duration;
			$countdown->{target_epoch} = $now + $duration;
			
			$countdown->{active} = 1;
			$countdown->{username} = $username;
			$countdown->{label} = "timer";
			$self->dirty(1);
			
			my $nice = $self->get_nice_countdown_desc($countdown);
			my $response = "";
			if ($prev_user) { $response = "Cancelled previous timer.  "; }
			$response .= "Starting timer for " . get_text_from_seconds($duration) . "...";
			
			return $response;
		} # start countdown
	} # value has non-whitespace
	else {
		# show current timer, if any
		if (!$countdown->{active}) {
			return "$username: There is no timer currently active in $chan.";
		}
		
		my $nice = $self->get_nice_countdown_desc($countdown);
		my $word = ($nice->{nice_remain} =~ /s$/i) ? "remain" : "remains";
		my $response = "Timer is active: " . $nice->{nice_remain} . " $word.";
		return $response;
	}
}

sub countdown {
	# countdown to a particular date/time, or next calendar event
	my ($self, $value, $args) = @_;
	my $username = $args->{who};
	my $chan = nch($args->{channel});
	
	$self->{data}->{channels} ||= {};
	my $channel_data = $self->{data}->{channels}->{sch($chan)} ||= {};
	my $countdown = $channel_data->{countdown} ||= {};
	
	if ($value =~ /\S/) {
		# start new countdown
		my $raw = $value;
		
		if ($raw =~ /^(stop|cancel|abort|off)/i) {
			# cancel countdown
			if (!$countdown->{active}) {
				return "$username: There is no countdown currently active in $chan.";
			}
			$countdown->{active} = 0;
			delete $channel_data->{countdown};
			$self->dirty(1);
			
			return "$username: Countdown has been cancelled.";
		}
		else {
			$raw =~ s/^(to|until)\s+//i;
			
			my $tz_name = $self->get_user_timezone($username) || 'local';
			# if (!$tz_name) { return "$username: Cannot use countdowns until you set your timezone.  Try !help timezone"; }
			
			my $prev_user = '';
			if ($countdown->{active}) {
				$prev_user = $countdown->{username};
				# return "$username: There is already a countdown active in this channel, started by user '".$countdown->{username}."'.  Type '!countdown stop' to cancel it.";
			}
			
			if ($raw =~ /calendar/i) {
				# get date/time from next calendar event
				my $cal_plug = $self->{bot}->{_eb_commands}->{calendar} || undef;
				if (!$cal_plug) {
					return "$username: The Google Calendar bot plugin is not enabled.";
				}
				
				my $event = $cal_plug->get_cal_event($chan, 'next');
				if ($event && ref($event)) {
					$countdown->{target_epoch} = $event->{CurrentStart};
					$countdown->{desc} = $event->{Title} || $event->{Description};
				}
				elsif ($event) {
					return "$username: $event";
				}
				else {
					return "$username: There are no upcoming events on the $chan calendar.";
				}
			}
			else {
				# try to parse date/time out of value
				my $alarm = $self->get_alarm_from_raw($raw, $tz_name);
				
				if ($alarm->{dt}->epoch() < time()) {
					# if user entered a time before now, jump ahead a day
					# handles cases such as "!countdown to midnight"
					$alarm->{dt}->add( days => 1 );
				}
				if ($alarm->{dt}->epoch() < time()) {
					# still in the past?  error out
					return "$username: Please enter a date and/or time in the future.";
				}
				
				$countdown->{target_epoch} = $alarm->{dt}->epoch();
				$countdown->{desc} = $alarm->{desc};
			} # parse date / time / title
			
			$countdown->{active} = 1;
			$countdown->{username} = $username;
			$countdown->{label} = "countdown";
			$self->dirty(1);
			
			my $nice = $self->get_nice_countdown_desc($countdown);
			my $response = "";
			if ($prev_user) { $response = "Cancelled previous countdown.  "; }
			$response .= "Starting countdown until ";
			if ($countdown->{desc}) { $response .= $countdown->{desc} . ", "; }
			my $word = ($nice->{nice_remain} =~ /s$/i) ? "remain" : "remains";
			$response .= $nice->{nice_when} . "... " . $nice->{nice_remain} . " $word.";
			return $response;
		} # start countdown
	} # value has non-whitespace
	else {
		# show current countdown, if any
		if (!$countdown->{active}) {
			return "$username: There is no countdown currently active in $chan.";
		}
		
		my $nice = $self->get_nice_countdown_desc($countdown);
		my $response = "Counting down until ";
		if ($countdown->{desc}) { $response .= $countdown->{desc} . ", "; }
		my $word = ($nice->{nice_remain} =~ /s$/i) ? "remain" : "remains";
		$response .= $nice->{nice_when} . "... " . $nice->{nice_remain} . " $word.";
		return $response;
	}
}

sub get_nice_countdown_desc {
	# return nice text for countdown, including target time and desc
	my $self = shift;
	my $countdown = shift;
	my $username = shift || $countdown->{username};
	my $tz_name = $self->get_user_timezone($username) || 'local';
	my $now = time();
	my $nice_remain = get_text_from_seconds( $countdown->{target_epoch} - $now );
	
	my $dt = DateTime->from_epoch( epoch => $countdown->{target_epoch}, time_zone => $tz_name );
	my $dt_now = DateTime->from_epoch( epoch => $now, time_zone => $tz_name );
	
	my $nice_when = '';
	if ($dt->ymd() ne $dt_now->ymd()) {
		$nice_when = $dt->day_name() . ', ' . $dt->day() . ' ' . $dt->month_name() . ' ';
	}
	else {
		if ($dt->hour() >= 12 + 6) { $nice_when .= "tonight "; }
		elsif ($dt->hour() < 12) { $nice_when .= "this morning "; }
		else { $nice_when .= "today "; }
	}
	my $nice_time = $dt->hour_12() . ':' . 
		sprintf("%02d", $dt->minute()) . ' ' . $dt->am_or_pm() . ' ' . $dt->time_zone_short_name();
	$nice_when .= 'at ' . $nice_time;
	
	return {
		nice_when => $nice_when,
		nice_remain => $nice_remain,
		nice_now => $nice_time
	};
}

sub alarm {
	# set/delete/list alarms
	my ($self, $value, $args) = @_;
	my $username = $args->{who};
	my $chan = nch($args->{channel});
	
	$self->{data}->{channels} ||= {};
	my $channel_data = $self->{data}->{channels}->{sch($chan)} ||= {};
	my $alarms = $channel_data->{alarms} ||= {};
	
	if ($value =~ /^(set|add)\s+(.+)$/i) {
		# set a new alarm
		my $raw = $2;
		
		my $tz_name = $self->get_user_timezone($username);
		if (!$tz_name) { return "$username: Cannot add alarms until you set your timezone.  Try !help timezone"; } 
		
		my $alarm = $self->get_alarm_from_raw($raw, $tz_name);
		$alarm->{username} = $username;
		delete $alarm->{dt};
		
		# store alarm in data
		my $alarm_key = '';
		if ($alarm->{year}) { $alarm_key .= 'y' . $alarm->{year}; }
		if ($alarm->{month}) { $alarm_key = 'm' . $alarm->{month}; }
		if ($alarm->{mday}) { $alarm_key .= 'd' . $alarm->{mday}; }
		if (defined($alarm->{wday})) { $alarm_key .= 'w' . $alarm->{wday}; }
		if (defined($alarm->{hour})) { $alarm_key .= 'h' . $alarm->{hour}; }
		if (defined($alarm->{minute})) { $alarm_key .= 'i' . $alarm->{minute}; }
		if ($alarm->{repeat}) { $alarm_key .= 'r'; }
		
		my $nice_desc = $self->get_nice_alarm_desc($alarm);
		
		if ($alarms->{$alarm_key}) {
			$alarms->{$alarm_key} = $alarm;
			$self->dirty(1);
			return "$username: Alarm updated: $nice_desc";
		}
		
		$alarms->{$alarm_key} = $alarm;
		$self->dirty(1);
		
		return "$username: Alarm set for: $nice_desc";
	} # set
	
	elsif ($value =~ /^(delete|del|remove|rem|cancel|abort|stop|off)\s+(.+)$/i) {
		my $which = $2;
		if (!scalar keys %$alarms) {
			if ($chan eq '#msg') { return "There are no private alarms set."; }
			else { return "$username: There are no alarms set for $chan."; }
		}
		
		if ($which =~ /all/i) {
			$channel_data->{alarms} = {};
			$self->dirty(1);
			if ($chan eq '#msg') { return "All private alarms deleted."; }
			else { return "$username: All alarms deleted for $chan."; }
		}
		if ($which !~ /^\d+$/) {
			return "$username: Invalid syntax.  Please specify the alarm number to delete.  Type !alarm list to see a list of them.";
		}
		
		my $alarm_keys = [ sort keys %$alarms ];
		my $alarm_key = $alarm_keys->[ int($which) - 1 ] || '';
		if (!$alarm_key) {
			return "$username: Alarm index '$which' not found.  Type !alarm list to see a list of alarms.";
		}
		
		delete $alarms->{$alarm_key};
		$self->dirty(1);
		
		return "$username: Alarm \#$which deleted.";
	} # delete
	
	elsif ($value =~ /^(list)/i) {
		if (!scalar keys %$alarms) {
			if ($chan eq '#msg') { return "There are no private alarms set."; }
			else { return "$username: There are no alarms set for $chan."; }
		}
		
		my $response = '';
		if ($chan eq '#msg') { $response = "Here are the private alarms set:\n"; }
		else { $response = "Here are the alarms set for $chan:\n"; }
		
		my $idx = 0;
		foreach my $alarm_key (sort keys %$alarms) {
			my $alarm = $alarms->{$alarm_key};
			$response .= "#" . int($idx + 1) . ": " . $alarm->{username} . ": " . $self->get_nice_alarm_desc($alarm, $username) . "\n";
			$idx++;
		}
		
		my $say_args = ($chan eq '#msg') ? { who => $username, channel => 'msg' } : { channel => nch($chan) };
		$self->say(
			%$say_args,
			body => $response
		);
		return undef;
	} # list
	
	return undef;
}

sub get_alarm_from_raw {
	# parse alarm attributes (time / date), as well as description, from raw text
	my ($self, $raw, $tz_name) = @_;
	
	my $dt = DateTime->from_epoch( epoch => time(), time_zone => $tz_name );
	my $alarm = { ampm => $dt->am_or_pm(), minute => 0 };
	
	# !alarm set 8:30
	# !alarm set daily 11 am
	# !alarm set weekly friday 12 pm
	# !alarm set june 5 12 am
	# !alarm set yearly 5 june 8:30 am
	# !alarm set 8:30 pm
	
	$raw =~ s/\btoday\b//i; # defaults to today, so can remove this word
	
	$raw =~ s/\bmidnight\b/12:00 am/i;
	$raw =~ s/\bnoon\b/12:00 pm/i;
	$raw =~ s/(\d+\:\d+)\:\d+/$1/; # strip seconds
	
	if ($raw =~ s/\b(\d+)\:(\d+)//i) {
		$alarm->{hour} = $1;
		$alarm->{minute} = $2;
	}
	if ($raw =~ s/\b(\d+)\s*(am|pm)\b//i) {
		$alarm->{hour} = $1;
		$alarm->{ampm} = $2;
	}
	if ($raw =~ s/\b(am|pm)\b//i) {
		$alarm->{ampm} = $1;
	}
	if ($alarm->{hour} < 13) {
		if ($alarm->{hour} == 12) { $alarm->{hour} = 0; }
		if ($alarm->{ampm} =~ /pm/i) { $alarm->{hour} += 12; }
	}
	delete $alarm->{ampm};
	
	if ($raw =~ s/\b$wday_re\b//i) {
		my $wday = $1;
		foreach my $key (keys %$wday_map) {
			if ($wday =~ /$key/i) {
				$alarm->{wday} = $wday_map->{$key};
				last;
			}
		}
	}
	
	if ($raw =~ s/\b$month_re\D*(\d+)\b//i) {
		$alarm->{month} = $1;
		$alarm->{mday} = $2;
	}
	elsif ($raw =~ s/\b(\d+)\D*$month_re\b//i) {
		$alarm->{mday} = $1;
		$alarm->{month} = $2;
	}
	
	if ($alarm->{month} =~ /$month_re/) {
		foreach my $key (keys %$month_map) {
			if ($alarm->{month} =~ /$key/i) {
				$alarm->{month} = $month_map->{$key};
				last;
			}
		}	
	}
	if ($raw =~ s/\b(\d{4})\D+(\d{1,2})\D+(\d{1,2})\b//i) {
		$alarm->{year} = $1;
		$alarm->{month} = $2;
		$alarm->{mday} = $3;
	}
	elsif ($raw =~ s/\b(\d{1,2})\D+(\d{1,2})\b//i) {
		$alarm->{month} = $1;
		$alarm->{mday} = $2;
	}
	elsif ($raw =~ s/\b(\d{4})\b//i) {
		$alarm->{year} = $1;
	}
	
	if ($raw =~ s/\b(daily|weekly|monthly|yearly)\b//i) {
		$alarm->{repeat} = 1;
	}
	if ($raw =~ s/\b(repeat|repeating|recurring)\b//i) {
		$alarm->{repeat} = 1;
	}
	
	if ($raw =~ s/\b(private)\b//i) {
		$alarm->{private} = 1;
	}
	
	$raw =~ s/\s+/ /g; # normalize whitespace
	$raw = trim($raw); # trim whitespace
	$alarm->{desc} = $raw;
	
	# convert alarm to local server timezone
	if ($alarm->{year}) { $dt->set_year( $alarm->{year} ); }
	if ($alarm->{month}) { $dt->set_month( $alarm->{month} ); }
	if ($alarm->{mday}) { $dt->set_day( $alarm->{mday} ); }
	$dt->set_hour( $alarm->{hour} || 0 );
	$dt->set_minute( $alarm->{minute} || 0 );
	$dt->set_second( 0 );
	
	if (defined($alarm->{wday})) {
		while ($alarm->{wday} != ($dt->day_of_week() % 7)) {
			$dt->add( days => 1 );
		}
	}
	
	$dt->set_time_zone( 'local' );
	$alarm->{hour} = $dt->hour();
	$alarm->{minute} = $dt->minute();
	
	return { %$alarm, dt => $dt };
}

sub get_nice_alarm_desc {
	# get nice, human readable description for alarm
	my $self = shift;
	my $alarm = shift;
	my $username = shift || $alarm->{username};
	my $tz_name = $self->get_user_timezone($username) || 'local';
	my $nice_desc = '';
	
	my $dt = DateTime->from_epoch( epoch => time(), time_zone => 'local' );
	$dt->set_hour( $alarm->{hour} || 0 );
	$dt->set_minute( $alarm->{minute} || 0 );
	$dt->set_time_zone( $tz_name );
	
	if (defined($alarm->{wday})) {
		my $weekdays = { 0 => 'Sunday', 1 => 'Monday', 2 => 'Tuesday', 3 => 'Wednesday', 4 => 'Thursday', 5 => 'Friday', 6 => 'Saturday' };
		$nice_desc .= $weekdays->{ $alarm->{wday} } . ' ';
	}
	if (defined($alarm->{month}) && defined($alarm->{mday})) {
		my $months = {
			1 => 'January', 2 => 'February', 3 => 'March', 4 => 'April', 5 => 'May', 6 => 'June',
			7 => 'July', 8 => 'August', 9 => 'September', 10 => 'October', 11 => 'November', 12 => 'December'
		};
		$nice_desc .= $alarm->{mday} . ' ' . $months->{ $alarm->{month} } . ' ';
	}
	if ($nice_desc) { $nice_desc .= 'at '; }
	$nice_desc .= trim($dt->strftime("%l:%M %p %Z"));
	
	if ($alarm->{repeat}) {
		$nice_desc .= " (recurring)";
	}
	if ($alarm->{desc}) {
		$nice_desc .= ': "' . $alarm->{desc} . '"';
	}
	
	return $nice_desc;
}

sub get_user_timezone {
	# try to determine user's timezone from db
	my $self = shift;
	my $username = shift;
	
	my $tz_name = '';
	if ($self->{data}->{users} && $self->{data}->{users}->{lc($username)}) {
		$tz_name = $self->{data}->{users}->{lc($username)}->{tz_name} || '';
	}
	
	return $tz_name;
}

sub tick {
	# Called every 0.1 seconds
	my $self = shift;
	my $min_key = int( time() / 60 );
	
	if (!$self->{_last_tick_minute} || ($min_key != $self->{_last_tick_minute})) {
		$self->{_last_tick_minute} = $min_key;
		
		my $dt = DateTime->from_epoch( epoch => time(), time_zone => 'local' );
		
		$self->{data}->{channels} ||= {};
		foreach my $chan (keys %{$self->{data}->{channels}}) {
			my $channel_data = $self->{data}->{channels}->{sch($chan)} ||= {};
			next unless $channel_data->{alarms};
			
			my $alarms = $channel_data->{alarms};
			foreach my $alarm_key (keys %$alarms) {
				my $alarm = $alarms->{$alarm_key};
				my $ring = 1;
				
				if (defined($alarm->{wday}) && ($dt->day_of_week() % 7 != $alarm->{wday})) { $ring = 0; }
				if (defined($alarm->{year}) && ($dt->year() != $alarm->{year})) { $ring = 0; }
				if (defined($alarm->{month}) && ($dt->month() != $alarm->{month})) { $ring = 0; }
				if (defined($alarm->{mday}) && ($dt->day() != $alarm->{mday})) { $ring = 0; }
				if (defined($alarm->{hour}) && ($dt->hour() != $alarm->{hour})) { $ring = 0; }
				if (defined($alarm->{minute}) && ($dt->minute() != $alarm->{minute})) { $ring = 0; }
				
				if ($ring) {
					# sound alarm
					my $nice_desc = $self->get_nice_alarm_desc($alarm);
					my $say_args = ($alarm->{private} || ($chan eq 'msg')) ? 
						{ who => $alarm->{username}, channel => 'msg' } : { channel => nch($chan) };
					
					$self->say(
						%$say_args,
						body => $alarm->{username} . ": [BEEP] Your alarm has gone off.  $nice_desc"
					);
					
					# delete if not recurring
					if (!$alarm->{repeat}) {
						delete $alarms->{$alarm_key};
					}
				} # alarm!
			} # foreach alarm
		} # foreach channel
	} # time to check alarms
	
	# countdowns
	my $sec_key = int( time() );
	if (!$self->{_last_tick_second} || ($sec_key != $self->{_last_tick_second})) {
		$self->{_last_tick_second} = $sec_key;
		
		$self->{data}->{channels} ||= {};
		foreach my $chan (keys %{$self->{data}->{channels}}) {
			my $channel_data = $self->{data}->{channels}->{sch($chan)} ||= {};
			next unless $channel_data->{countdown};
			
			my $countdown = $channel_data->{countdown};
			if ($countdown->{active}) {
				my $sec_remain = int( $countdown->{target_epoch} - $sec_key );
				my $response  = "";
				
				if ($sec_remain < 1) {
					# countdown complete!
					my $label = ucfirst( $countdown->{label} );
					my $nice = $self->get_nice_countdown_desc($countdown);
					$response = $countdown->{username} . ": [BEEP] $label complete! ";
					if ($countdown->{desc}) { $response .= $countdown->{desc} . ", "; }
					$response .= $nice->{nice_now} . ".";
					
					# deactivate countdown
					$countdown->{active} = 0;
					delete $channel_data->{countdown};
					$self->dirty(1);
				}
				else {
					my $min_remain = int( $sec_remain / 60 );
					my $hour_remain = int( $min_remain / 60 );
					my $notify = 0;
					
					if ($sec_remain <= 5) { $notify = 1; }
					elsif (($sec_remain <= 10) && ($sec_remain % 5 == 0)) { $notify = 1; }
					elsif (($sec_remain <= 60) && ($sec_remain % 30 == 0)) { $notify = 1; }
					elsif ($sec_remain % 60 == 0) {
						if ($min_remain <= 5) { $notify = 1; }
						elsif (($min_remain <= 30) && ($min_remain % 5 == 0)) { $notify = 1; }
						elsif (($min_remain <= 60) && ($min_remain % 15 == 0)) { $notify = 1; }
						elsif ($min_remain % 60 == 0) {
							if ($hour_remain <= 24) { $notify = 1; }
							elsif ($hour_remain % 24 == 0) { $notify = 1; }
						}
					}
					
					if ($notify) {
						my $label = ucfirst( $countdown->{label} );
						my $nice = $self->get_nice_countdown_desc($countdown);
						my $word = ($nice->{nice_remain} =~ /s$/i) ? "remain" : "remains";
						if ($sec_remain <= 5) {
							$response = "$label: " . $nice->{nice_remain} . "...";
						}
						elsif (($sec_remain <= 60) || ($label =~ /timer/i)) {
							$response = "$label: " . $nice->{nice_remain} . " $word...";
						}
						else {
							$response = "Countdown until " . ($countdown->{desc} || $nice->{nice_when}) . ": " . $nice->{nice_remain} . " $word...";
						}
					}
				} # countdown not yet complete
				
				if ($response) {
					my $say_args = ($chan eq 'msg') ? 
						{ who => $countdown->{username}, channel => 'msg' } : { channel => nch($chan) };
					
					$self->say(
						%$say_args,
						body => $response
					);
				}
			} # active countdown
		} # foreach channel
	} # time to check countdowns
}

1;
