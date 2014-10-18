package SimpleBot::Plugin::Calc;

##
# Calc.pm
# SimpleBot Plugin
# Copyright (c) 2013 Joseph Huckaby
# MIT Licensed
#
# !calc 1 + 2
# !convert 45 lb to kg
# !rand 100
# !rand 1 - 5
# !rand 99.5
# !roll 1d6
# !pick
##

use strict;
use FileHandle;
use Math::Units;
use base qw( SimpleBot::Plugin );
use Digest::MD5 qw(md5_hex md5);
use Time::HiRes qw/time/;
use MIME::Base64;
use URI::Escape;
use Tools;

sub init {
	my $self = shift;
	$self->register_commands('calc', 'convert', 'rand', 'roll', 'dice', 'hash', 'md5', 'pick', 'b64encode', 'b64decode', 'urlencode', 'urldecode');
}

sub pick {
	# pick a random user from the channel, and notify them
	my ($self, $msg, $args) = @_;
	my $username = $args->{who};
	my $chan = $args->{channel};
	
	if ($chan eq 'msg') {
		return "You can only use pick in a #channel.";
	}
	
	my $channel = $self->{bot}->{_eb_channels}->{ sch(lc($args->{channel})) } ||= {};
	my $users = [];
	foreach my $nick (keys %$channel) {
		if (($nick !~ /(bot|serv)$/i) && (lc($nick) ne lc($self->{bot}->{params}->{nick}))) {
			push @$users, $channel->{$nick};
		}
	}
	
	if (!@$users) { return "$username: There are no users in $chan to choose from."; }
	
	my $chosen = $users->[ int(ultra_rand(scalar @$users)) ];
	return "$username: The chosen one is: $chosen";
}

sub urlencode {
	# URL encode a string
	my ($self, $msg, $args) = @_;
	return "URL Encoded: " . uri_escape(trim($msg));
}

sub urldecode {
	# URL decode a string
	my ($self, $msg, $args) = @_;
	return "URL Decoded: " . uri_unescape(trim($msg));
}

sub b64encode {
	# base64 encode a string
	my ($self, $msg, $args) = @_;
	return "Base64 Encoded: " . encode_base64(trim($msg));
}

sub b64decode {
	# base64 decode a string
	my ($self, $msg, $args) = @_;
	return "Base64 Decoded: " . decode_base64(trim($msg));
}

sub hash {
	# generate md5 hash using provided string, or utterly random
	my ($self, $msg, $args) = @_;
	
	if (!$msg) { $msg = time() . $$ . rand(1); }
	return "MD5: " . md5_hex( $msg );
}
sub md5 { return hash(@_); }

sub rand {
	# generate random numbers
	my ($self, $msg, $args) = @_;
	my $username = $args->{who};
	my $chan = $args->{channel};
	
	my $low = "0";
	my $high = "1.0";
	
	if ($msg =~ /([\d\.]+)\D+([\d\.]+)/) {
		($low, $high) = ($1, $2);
	}
	elsif ($msg =~ /(\d+(\.\d+)?)/) {
		$high = $1;
	}
	else {
		$msg .= "0.0 - 1.0";
	}
	
	my $value = ultra_rand($high - $low) + $low;
	if ($msg !~ /\d\.\d/) { $value = int($value); }
	
	return "Random: $value";
}

sub roll {
	# roll dice for RPGs
	my ($self, $msg, $args) = @_;
	my $username = $args->{who};
	my $chan = $args->{channel};
	my $value = 0;
	my $orig_msg = '' . $msg;
	
	my $actions = [];
	
	while ($msg =~ s/(\d+)d(\d+)//) {
		my ($num, $sides) = ($1, $2);
		for (1..$num) {
			my $result = int( ultra_rand($sides) ) + 1;
			push @$actions, "[$result]";
			$value += $result; 
		}
	}
	while ($msg =~ s/\+\s*(\d+)//) {
		my $num = int($1);
		push @$actions, "+$num";
		$value += $num; 
	}
	while ($msg =~ s/\-\s*(\d+)//) {
		my $num = int($1);
		push @$actions, "-$num";
		$value -= $num; 
	}
	
	if (!@$actions) { return "$username: Invalid format for dice roll.  Try !roll 1d6"; }
	
	return "Dice Roll for $username: $orig_msg = " . join(' ', @$actions) . " = $value";
}
sub dice { return roll(@_); }

sub calc {
	# simple calculator
	my ($self, $msg, $args) = @_;
	my $username = $args->{who};
	my $chan = $args->{channel};
	
	my $orig_msg = $msg;
	$msg =~ s/[^\d\.\+\-\*\/\(\)\%\^]+//g;
	if (!$msg) { return "$username: Invalid syntax for calculator."; }
	
	my $result = '';
	eval {
		eval '$result = ' . $msg . ';';
		if ($@) { die "$@\n"; }
	};
	if ($@) {
		my $error_msg = trim($@); 
		# at (eval 145) line 1,
		$error_msg =~ s/\s+at\s+\(eval\s+\d+\)\s+line\s+\d+\,?//;
		return "$username: Calculator error: $error_msg";
	}
	
	return "$username: $orig_msg = $result";
}

sub convert {
	# use Math::Units to convert things
	my ($self, $msg, $args) = @_;
	my $username = $args->{who};
	my $chan = $args->{channel};
	
	if ($msg =~ /^([\d\.]+)\s*(\S+).+?(\S+)$/) {
		my ($value, $from, $to) = ($1, $2, $3);
		my $result = '';
		eval {
			$result = Math::Units::convert($value, $from, $to);
		};
		if ($@) {
			my $error_msg = trim($@); $error_msg =~ s/\s+at\s+\S+\s+line\s+\d+//;
			return "$username: Conversion failed: $error_msg";
		}
		
		return "$username: $value $from = $result $to";
	}
	else {
		return "$username: Invalid syntax for convert, use: !convert 10 lb to kg, or !convert 45 C to F";
	}
	
	return undef;
}

1;
