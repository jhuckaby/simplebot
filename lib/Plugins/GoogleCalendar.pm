package SimpleBot::Plugin::GoogleCalendar;

##
# GoogleCalendar.pm
# SimpleBot Plugin
# Copyright (c) 2013 Joseph Huckaby
# MIT Licensed
#
# !calendar set iu9de9ell3bhagnk1con4052q0
# !calendar current
# !calendar next
# !calendar refresh
# !calendar delete
##

use strict;
use DateTime;
use base qw( SimpleBot::Plugin );
use Tools;
use URI::Escape;

my $wday_map = {
	'SU' => 0,
	'MO' => 1,
	'TU' => 2,
	'WE' => 3,
	'TH' => 4,
	'FR' => 5,
	'SA' => 6
};

sub init {
	my $self = shift;
	$self->register_commands('calendar', 'cal', 'current', 'next');
}

sub calendar {
	# umbrella command for all the other commands
	my ($self, $cmd, $args) = @_;
	my $username = $args->{who};
	
	if ($cmd =~ /^(\w+)(.*)$/) {
		my ($sub_cmd, $value) = ($1, $2);
		$value = trim($value);
		if ($self->can($sub_cmd)) { return $self->$sub_cmd($value, $args); }
		else { return "$username: Unknown calendar command: $sub_cmd"; }
	}
	
	return undef;
}
sub cal { return calendar(@_); }

sub set {
	# set new calendar id
	my ($self, $msg, $args) = @_;
	my $username = $args->{who};
	my $chan = $args->{channel};
	
	if ($chan eq 'msg') { return "$username: Sorry, you can only add calendars to #channels."; }
	if ($msg !~ /^\w+$/) { return "$username: Invalid calendar ID.  Please see '!help calendar' for instructions."; }
	
	$self->{data}->{channels} ||= {};
	$self->{data}->{channels}->{sch(lc($chan))} = $msg;
	$self->dirty(1);
	
	return $self->refresh($msg, $args);
}

sub current {
	# emit current event from cal
	my ($self, $msg, $args) = @_;
	my $username = $args->{who};
	my $chan = $args->{channel};
	my $tz_name = '';
	
	if ($msg =~ /\S/) {
		$tz_name = find_timezone_name( $msg );
		if (!$tz_name) { return "$username: Could not determine timezone.  Please type '!help timezone' for formatting hints."; }
	}
	
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		who => $args->{who_disp},
		run => sub {
			my $event = $self->get_cal_event($chan, 'current', $tz_name);
			if ($event && ref($event)) {
				print "Current Event: " . trim($event->{Title} || $event->{Description}) . " (started ".$event->{NiceWhen}.")\n";
			}
			elsif ($event) {
				print "$event\n";
			}
			else {
				print "No current event was found on the $chan calendar.\n";
			}
		}
	);
	
	return undef;
}

sub next {
	# emit next item from cal
	my ($self, $msg, $args) = @_;
	my $username = $args->{who};
	my $chan = $args->{channel};
	my $tz_name = '';
	
	if ($msg =~ /\S/) {
		$tz_name = find_timezone_name( $msg );
		if (!$tz_name) { return "$username: Could not determine timezone.  Please type '!help timezone' for formatting hints."; }
	}
	
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		who => $args->{who_disp},
		run => sub {
			my $event = $self->get_cal_event($chan, 'next', $tz_name);
			if ($event && ref($event)) {
				print "Next Event: " . trim($event->{Title} || $event->{Description}) . " ".$event->{NiceWhen}."\n";
			}
			elsif ($event) {
				print "$event\n";
			}
			else {
				print "There are no upcoming events on the $chan calendar.\n";
			}
		}
	);
	
	return undef;
}

sub refresh {
	# refresh calendar from google
	my ($self, $msg, $args) = @_;
	my $username = $args->{who};
	my $chan = $args->{channel};
	
	$self->{data}->{channels} ||= {};
	my $cal_id = $self->{data}->{channels}->{sch(lc($chan))} || '';
	if (!$cal_id) { return "$username: You have not set a calendar ID for $chan yet.  Try !calendar set YOUR_GOOGLE_CALENDAR_ID"; }
	
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		who => $args->{who_disp},
		run => sub {
			# download calendar ICS file and store it locally
			if ($cal_id !~ /\@/) { $cal_id .= '@group.calendar.google.com'; }
			my $cal_url = 'http://www.google.com/calendar/ical/'.uri_escape($cal_id).'/public/basic.ics';
			$self->log_debug(8, "Fetching $chan calendar from google: $cal_url");
			
			my $resp = wget($cal_url);
			if ($resp->is_success()) {
				my $cal_file = 'data/' . $self->{params}->{server} . '/calendar-'.sch(lc($chan)).'.ics';
				print "$username: Okay, the ".nch($chan)." calendar has been ".((-e $cal_file) ? "updated" : "loaded").".\n";
				save_file( $cal_file, $resp->content() );
			}
			else {
				print "$username: Failed to fetch your calendar data: " . $resp->status_line() . "\n";
			}
		}
	);
	
	return undef;
}

sub delete {
	# remove calendar from current channel
	my ($self, $msg, $args) = @_;
	my $username = $args->{who};
	my $chan = $args->{channel};
	
	$self->{data}->{channels} ||= {};
	my $cal_id = $self->{data}->{channels}->{sch(lc($chan))} || '';
	if (!$cal_id) { return "$username: No calendar found for $chan."; }
	
	my $cal_file = 'data/' . $self->{params}->{server} . '/calendar-'.sch(lc($chan)).'.ics';
	unlink $cal_file;
	
	delete $self->{data}->{channels}->{sch(lc($chan))};
	$self->dirty(1);
	
	return "$username: Calendar has been deleted for channel $chan.";
}

sub get_cal_event {
	# get current and next events from calendar
	my $self = shift;
	my $chan = shift;
	my $type = shift;
	my $disp_tz_name = shift || '';
	
	my $cal_file = 'data/' . $self->{params}->{server} . '/calendar-'.sch(lc($chan)).'.ics';
	my $stats = [ stat($cal_file) ];
	if (!$stats->[9]) { return "ERROR: No calendar was found for $chan.  Please use: !calendar set YOUR_GOOGLE_CALENDAR_ID"; }
	
	# auto-refresh every N seconds
	if (time() - $stats->[9] >= $self->{config}->{CheckFreq}) {
		$self->{data}->{channels} ||= {};
		my $cal_id = $self->{data}->{channels}->{sch(lc($chan))} || '';
		if ($cal_id) {
			if ($cal_id !~ /\@/) { $cal_id .= '@group.calendar.google.com'; }
			my $cal_url = 'http://www.google.com/calendar/ical/'.uri_escape($cal_id).'/public/basic.ics';
			$self->log_debug(8, "Fetching $chan calendar from google: $cal_url");
			my $resp = wget($cal_url, 5);
			if ($resp->is_success()) {
				save_file( $cal_file, $resp->content() );
			}
		}
	}
	
	my $cal_raw = load_file( $cal_file );
	$cal_raw =~ s/\r\n/\n/sg; $cal_raw =~ s/\r/\n/sg; # fix line endings, in case they are dos
	
	my $default_tz = 0;
	my $events = [];
	my $event = undef;
	
	foreach my $line (split(/\n/, $cal_raw)) {
		$line = trim($line);
		next unless $line =~ /\S/;
		
		# TZID:America/Toronto
		my $matches = [];
		if (preg_match('/^TZID\:(.+)$/', $line, $matches)) { $default_tz = $matches->[1]; }
		
		# BEGIN:VEVENT
		if (preg_match('/^(BEGIN\:VEVENT)/', $line)) {
			$event = {
				'Start' => '',
				'End' => '',
				'Duration' => '',
				'Freq' => '',
				'ByDay' => '',
				'ByMonthDay' => '',
				'Count' => '',
				'Until' => '',
				'Title' => '',
				'Description' => '',
				'ID' => '',
				'DispTimeZone' => $disp_tz_name
			};
		}
		
		if ($event) {
			# DTSTART;TZID=America/Los_Angeles:20110622T230000
			# DTSTART:20110628T163000Z
			if (preg_match('/^DTSTART/', $line)) {
				$event->{Start} = parse_cal_date( $line );
			}
			
			# DTEND;TZID=America/Los_Angeles:20110623T000000
			# DTEND:20110628T183000Z
			if (preg_match('/^DTEND/', $line)) {
				$event->{End} = parse_cal_date( $line );
			}
			
			# RRULE:FREQ=YEARLY
			# RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR
			# RRULE:FREQ=MONTHLY;BYMONTHDAY=22
			# RRULE:FREQ=DAILY
			# RRULE:FREQ=WEEKLY;COUNT=10;BYDAY=WE
			# RRULE:FREQ=WEEKLY;UNTIL=20110727T160000Z;BYDAY=WE
			# RRULE:FREQ=MONTHLY;BYDAY=4WE
			if (preg_match('/RRULE\:/', $line)) {
				if (preg_match('/FREQ\=(\w+)/', $line, $matches)) { $event->{Freq} = $matches->[1]; }
				if (preg_match('/BYDAY\=([\w\,]+)/', $line, $matches)) { $event->{ByDay} = $matches->[1]; }
				if (preg_match('/BYMONTHDAY\=(\d+)/', $line, $matches)) { $event->{ByMonthDay} = $matches->[1]; }
				if (preg_match('/COUNT\=(\d+)/', $line, $matches)) { $event->{Count} = $matches->[1]; }
				if (preg_match('/UNTIL\=(\d+\w+)/', $line, $matches)) { $event->{Until} = parse_cal_date($matches->[1]); }
			}
			
			# SUMMARY:This is a yearly event
			if (preg_match('/^SUMMARY\:(.+)$/', $line, $matches)) { $event->{Title} = preg_replace('/\\\\/', '', $matches->[1]); }
			
			# DESCRIPTION:Yearly yo
			if (preg_match('/^DESCRIPTION\:(.+)$/', $line, $matches)) { $event->{Description} = $matches->[1]; }
			
			# UID:tpk027ole6vf9nqvtu74dqkmh8@google.com
			if (preg_match('/^UID\:(.+)$/', $line, $matches)) { $event->{ID} = $matches->[1]; }
			
			# ;TZID=America/Los_Angeles
			if (preg_match('/\bTZID\=([\w\/]+)/', $line, $matches)) { $event->{TimeZone} = $matches->[1]; }
		}
		
		# END:VEVENT
		if (preg_match('/^(END\:VEVENT)/', $line)) {
			if (!$event->{ID}) { $event->{ID} = generate_unique_id(); }
			$event->{Duration} = $event->{End} - $event->{Start};
			$event->{TimeZone} ||= $default_tz;
			$event->{dargs} = DateTime->from_epoch( epoch => $event->{Start}, time_zone => $event->{TimeZone} );
			
			push @$events, $event;
			$event = undef;
		}
	} # foreach line in ics file

	# process events
	my $now = time();
	
	my $cur_event = find_current_event( $events, $now );
	if ($cur_event) { delete $cur_event->{dargs}; }
	
	if ($type eq 'current') {
		if ($cur_event) { add_event_metadata($cur_event); }
		return $cur_event;
	}
	
	# try to find "next" event in the future
	# only scan N weeks out, as this is brute force and slow
	my $next_event = undef;
	my $max_halfs = 336 * 4; # 4 weeks
	
	for (my $idx = 0; $idx < $max_halfs; $idx++) {
		$now += 1800;
		$next_event = find_current_event( $events, $now );
		if ($next_event) {
			if (!$cur_event || ($cur_event->{CurrentStart} != $next_event->{CurrentStart})) {
				# bingo, found next event, exit loop
				$idx = $max_halfs;
			}
			else {
				# found same event as current, so skip it
				$next_event = undef;
			}
		}
	}
	
	if ($next_event) {
		delete $next_event->{dargs};
		add_event_metadata($next_event);
	}
	
	return $next_event;
}

sub add_event_metadata {
	# add time/date into to event, for display purposes
	my $event = shift;
	my $tz_name = $event->{DispTimeZone} || $event->{TimeZone};
	
	my $dt = DateTime->from_epoch( epoch => $event->{CurrentStart}, time_zone => $tz_name );
	my $dt_now = DateTime->from_epoch( epoch => time(), time_zone => $tz_name );
	my $nice_when = '';
	if ($dt->ymd() ne $dt_now->ymd()) {
		$nice_when = 'on ' . $dt->day_name() . ', ' . $dt->day() . ' ' . $dt->month_name() . ' ';
	}
	else {
		if ($dt->hour() >= 12 + 6) { $nice_when .= "tonight "; }
		elsif ($dt->hour() < 12) { $nice_when .= "this morning "; }
		else { $nice_when .= "today "; }
	}
	$nice_when .= 'at ' . $dt->hour_12() . ':' . sprintf("%02d", $dt->minute()) . ' ' . $dt->am_or_pm() . ' ' . $dt->time_zone_short_name();
	
	$event->{NiceWhen} = $nice_when;
}

sub find_current_event {
	# scan all events for one that is currently active
	my ($events, $now) = @_;
	my $dargs_now = DateTime->from_epoch( epoch => $now );
	my $cur_event = undef;
	my $cur_start_time = 0;
	
	foreach my $event (@$events) {
		if ($cur_start_time = check_event( $event, $now, $dargs_now )) {
			$cur_event = { %$event };
			$cur_event->{CurrentStart} = $cur_start_time;
			last;
		}
	}
	
	return $cur_event;
}

sub check_event {
	# process single event, and see if it matches current
	my ($event, $now, $dargs_now) = @_;
	my $dargs = $event->{dargs};
	$dargs_now->set_time_zone( $event->{TimeZone} );
	
	if ($now < $event->{Start}) { return 0; }
	if ($event->{Until} && ($now > $event->{Until})) { return 0; }
	
	my $freq = lc($event->{Freq});
	my $matches = undef;
	
	if ($event->{Count}) {
		# this is exact for yearly and monthly
		# but approximated for weekly and daily
		if ($freq eq 'yearly') {
			if ($dargs_now->year() - $dargs->year() >= $event->{Count}) { return 0; }
		}
		elsif ($freq eq 'monthly') {
			my $start = ($dargs->year() * 12) + $dargs->month();
			my $end = ($dargs_now->year() * 12) + $dargs->month();
			if ($end - $start >= $event->{Count}) { return 0; }
		}
		elsif ($freq eq 'weekly') {
			# RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR
			my $start = ($dargs->year() * 52) + (($dargs->day_of_year() - 1) / 7);
			my $end = ($dargs_now->year() * 52) + (($dargs_now->day_of_year() - 1) / 7);
			my $mult = 1;
			if (preg_match('/\,/', $event->{ByDay})) {
				$mult = scalar split(/\,\s*/, $event->{ByDay});
			}
			if (($end - $start) * $mult >= $event->{Count}) { return 0; }
		}
		elsif ($freq eq 'daily') {
			my $start = ($dargs->year() * 365.25) + ($dargs->day_of_year() - 1);
			my $end = ($dargs_now->year() * 365.25) + ($dargs_now->day_of_year() - 1);
			if ($end - $start >= $event->{Count}) { return 0; }
		}
	} # count
	
	my $dt = DateTime->new(
		year       => $dargs_now->year(),
		month      => $dargs_now->month(),
		day        => $dargs_now->day(),
		hour       => $dargs->hour(),
		minute     => $dargs->minute(),
		second     => $dargs->second(),
		nanosecond => 0,
		time_zone  => $event->{TimeZone}
	);
	my $todays_run = $dt->epoch();
	
	if ($freq eq 'yearly') {
		# yearly
		if ($dargs->day_of_year() == $dargs_now->day_of_year()) {
			if (($now >= $todays_run) && ($now < ($todays_run + $event->{Duration}))) {
				return $todays_run;
			}
		}
	}
	elsif ($freq eq 'monthly') {
		# monthly
		if (preg_match('/^(\d+)(\w+)/', $event->{ByDay}, $matches)) {
			# RRULE:FREQ=MONTHLY;BYDAY=4WE
			my $num = $matches->[1];
			my $wday = $matches->[2];
			if ($dargs_now->day_of_week() % 7 == $wday_map->{$wday}) {
				if (int($dargs_now->day() / 7) + 1 == $num) {
					if (($now >= $todays_run) && ($now < ($todays_run + $event->{Duration}))) {
						return $todays_run;
					}
				} # right week
			} # right day of week
		}
		else {
			# RRULE:FREQ=MONTHLY;BYMONTHDAY=22
			my $mday = $event->{ByMonthDay} || $dargs->day();
			if ($mday == $dargs_now->day()) {
				if (($now >= $todays_run) && ($now < ($todays_run + $event->{Duration}))) {
					return $todays_run;
				}
			}
		}
	}
	elsif ($freq eq 'weekly') {
		# weekly
		# RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR
		my $wdays = {};
		if ($event->{ByDay}) {
			foreach my $wday (split(/\,\s*/, $event->{ByDay})) {
				$wdays->{ $wday_map->{$wday} } = 1;
			}
		}
		else { $wdays->{ int($dargs->day_of_week() % 7) } = 1; }
		
		if ($wdays->{ int($dargs_now->day_of_week() % 7) }) {
			if (($now >= $todays_run) && ($now < ($todays_run + $event->{Duration}))) {
				return $todays_run;
			}
		}
	}
	elsif ($freq eq 'daily') {
		# daily
		if (($now >= $todays_run) && ($now < ($todays_run + $event->{Duration}))) {
			return $todays_run;
		}
	}
	else {
		# default, no repeat
		if (($now >= $event->{Start}) && ($now < $event->{End})) {
			return $event->{Start};
		}
	}
	
	# this event is not currently active
	return 0;
}

sub parse_cal_date {
	# parse date/time into epoch given one of the following formats:
	# DTSTART;TZID=America/Los_Angeles:20110622T230000
	# DTSTART:20110628T163000Z
	my $text = shift;
	my $epoch = 0;
	my $tz = 0;
	if ($text =~ /TZID=([\w\/]+)/) { $tz = $1; }
	
	if ($text =~ /(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})/) {
		my ($yyyy, $mm, $dd, $hh, $mi, $ss) = ($1, $2, $3, $4, $5, $6);
		
		my $dt = 0;
		eval {
			$dt = DateTime->new(
				year       => $yyyy,
				month      => $mm,
				day        => $dd,
				hour       => $hh,
				minute     => $mi,
				second     => $ss,
				nanosecond => 0,
				time_zone  => $tz
			);
		};
		if ($dt) { $epoch = $dt->epoch(); }
	} # found date/time stamp
	
	return $epoch;
}

1;
