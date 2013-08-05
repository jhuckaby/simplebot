package SimpleBot::Plugin::Calc;

##
# Calc.pm
# SimpleBot Plugin
# Copyright (c) 2013 Joseph Huckaby
# MIT Licensed
#
# !calc 1 + 2
# !convert 45 lb to kg
##

use strict;
use Math::Units;
use base qw( SimpleBot::Plugin );
use Tools;

sub init {
	my $self = shift;
	$self->register_commands('calc', 'convert');
}

sub calc {
	# simple calculator
	my ($self, $msg, $args) = @_;
	my $username = $args->{who};
	my $chan = $args->{channel};
	
	my $orig_msg = $msg;
	$msg =~ s/[^\d\+\-\*\/\(\)\%\^]+//g;
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
