package SimpleBot::Plugin::GoogleSearch;

##
# Google.pm
# SimpleBot Plugin
# Copyright (c) 2013 Joseph Huckaby
# MIT Licensed
##

use strict;
use base qw( SimpleBot::Plugin );
use Tools;
use HTTP::Date;
use URI::Escape;

sub init {
	my $self = shift;
	$self->register_commands('google', 'define');
}

sub google {
	# google search, return first result whatever it is
	my ($self, $value, $args) = @_;
	
	my $prefix = "Google Result";
	my $username = $args->{who};
	my $users = $self->{bot}->{_eb_temp}->{channels}->{sch($args->{channel})}->{users} || {};
	
	if ($users->{lc($value)} && $users->{lc($value)}->{last_said}) {
		# user wants to translate the last thing said by the given user
		my $target_nick = $value;
		$value = trim($users->{lc($value)}->{last_said}->{raw_body});
		$prefix = "$target_nick: $value";
	}
	if (!$value && $users->{lc($username)} && $users->{lc($username)}->{last_said}) {
		# no value?  then let's translate the last thing WE said
		$value = trim($users->{lc($username)}->{last_said}->{raw_body} || '');
	}
	return unless $value;
		
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		run => sub {
			eval {
				my $url = 'http://www.google.com/uds/GwebSearch?callback=receive_google_search_results&context=0&lstkp=0&rsz=large&hl=en&source=gsc&gss=.com&sig=&q='.uri_escape($value).'&key=notsupplied&v=1.0';
				$self->log_debug(9, "Fetching URL: $url");
				my $google = file_get_contents( $url );
				
				my $items = [];
				while ($google =~ s@\"titleNoFormatting\"\:"([^\"]+)\"@@) {
					my $title = $1;
					$title =~ s/\\x(\w{2})/\%$1/g;
					$title = uri_unescape( $title );
					
					if (!($google =~ s@\"unescapedUrl\"\:\"([^\"]+)\"@@)) { last; }
					my $link = $1;
					
					push @$items, "$title: $link";
				}
				
				if (@$items) {
					my $item = shift @$items;
					print "$prefix: $item\n";
					
					my $result_queue_file = 'data/' . $self->{params}->{server} . '/result-queue-' . sch($args->{channel}) . '.txt';
					save_file( $result_queue_file, join("\n", map { 'Google Result: ' . $_; } @$items) . "\n" );
				}
				else {
					print "No results for: $value\n";
				}
			}; # eval
			if ($@) { $self->log_debug(1, "CHILD CRASH google: $@"); }
		} # sub
	);
}

sub define {
	# define term using unofficial google api
	my ($self, $value, $args) = @_;
	
	return unless $value;
	
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		run => sub {
			eval {
				my $url = 'http://www.google.com/dictionary/json?callback=dict_api.callbacks.id100&q='.uri_escape($value).'&sl=en&tl=en&restrict=pr,de&client=te';
				$self->log_debug(9, "Fetching URL: $url");
				my $google = file_get_contents( $url );
				
				my $meaning = '';
				if ($google =~ m@\"meaning\"\,\"terms\"\:\[\{\"type\"\:\"text\"\,\"text\"\:\"([^\"]+)\"@) {
					$meaning = $1;
					$meaning =~ s/\\x(\w{2})/\%$1/g;
					$meaning =~ s/\n/ /g;
					$meaning = uri_unescape( $meaning );
					$meaning = decode_entities( $meaning );
				}
				
				if ($meaning) {
					print ucfirst($value) . ": $meaning\n";
				}
				else {
					print "No definition found for: $value\n";
				}
			}; # eval
			if ($@) { $self->log_debug(1, "CHILD CRASH define: $@"); }
		} # sub
	);
}

1;
