package SimpleBot::Plugin::WebSearch;

##
# WebSearch.pm
# SimpleBot Plugin
# Copyright (c) 2013 Joseph Huckaby
# MIT Licensed
##

use strict;
use base qw( SimpleBot::Plugin );
use Tools;
use HTTP::Date;
use URI::Escape;
use Encode qw(decode encode);

sub init {
	my $self = shift;
	$self->register_commands('google', 'define', 'image');
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
	
	$self->log_debug(9, "Forking for Google Search API...");
		
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		handler => '_fork_utf8_said',
		run => sub {
			eval {
				my $items = $self->_google_search($value);
				if (@$items) {
					my $item = shift @$items;
					my $text = $item->{title} . ": " . $item->{link};
					print "$prefix: " . encode('UTF-8', $text, Encode::FB_QUIET) . "\n";
					
					# my $result_queue_file = 'data/' . $self->{params}->{server} . '/result-queue-' . sch($args->{channel}) . '.txt';
					# save_file( $result_queue_file, join("\n", map { 'Google Result: ' . $_; } @$items) . "\n" );
				}
				else {
					print "No results for: $value\n";
				}
			}; # eval
			if ($@) { $self->log_debug(1, "CHILD CRASH google: $@"); }
		} # sub
	);
}

sub image {
	# google image search, return first result whatever it is
	my ($self, $value, $args) = @_;
	
	my $username = $args->{who};
	my $users = $self->{bot}->{_eb_temp}->{channels}->{sch($args->{channel})}->{users} || {};
	
	if ($users->{lc($value)} && $users->{lc($value)}->{last_said}) {
		# user wants to translate the last thing said by the given user
		my $target_nick = $value;
		$value = trim($users->{lc($value)}->{last_said}->{raw_body});
	}
	if (!$value && $users->{lc($username)} && $users->{lc($username)}->{last_said}) {
		# no value?  then let's translate the last thing WE said
		$value = trim($users->{lc($username)}->{last_said}->{raw_body} || '');
	}
	return unless $value;
	
	my $result_file = 'data/' . $self->{params}->{server} . '/last-image-search-result-' . sch($args->{channel}) . '.json';
	
	# if searching for same thing repeatedly, pick random result from last set
	if ($self->{last_image_search_query} && ($self->{last_image_search_query} eq $value) && (-e $result_file)) {
		my $last_results = eval { json_parse( load_file($result_file) ); };
		if ($last_results && @$last_results) {
			my $chosen = shift @$last_results;
			if ($chosen && $chosen->{link}) {
				if (@$last_results) {
					save_file( $result_file, json_compose_pretty($last_results) );
				}
				else { unlink $result_file; }
				
				return $chosen->{link};
			}
		}
		unlink $result_file;
	}
	$self->{last_image_search_query} = $value;
	
	$self->log_debug(9, "Forking for Google Image Search API...");
	unlink $result_file;
	
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		handler => '_fork_utf8_said',
		run => sub {
			eval {
				my $items = $self->_google_image_search($value);
				
				if (!$items) {
					# retry once after a 2s delay (Google is weird)
					sleep 2;
					$items = $self->_google_image_search($value);
					if (!$items) {
						print "Google Error: Image Search API Rate Exceeded.  Please wait a few seconds before trying again.\n";
						unlink $result_file;
						return;
					}
				}
				
				if ($items && @$items) {
					my $item = shift @$items;
					print encode('UTF-8', $item->{link}, Encode::FB_QUIET) . "\n";
					
					if (!save_file( $result_file, json_compose_pretty($items) )) {
						$self->log_debug(9, "Failed to save result file: $result_file: $!");
					}
					# my $result_queue_file = 'data/' . $self->{params}->{server} . '/result-queue-' . sch($args->{channel}) . '.txt';
					# save_file( $result_queue_file, join("\n", map { 'Google Result: ' . $_; } @$items) . "\n" );
				}
				else {
					print "No results for: $value\n";
					unlink $result_file;
				}
			}; # eval
			if ($@) { $self->log_debug(1, "CHILD CRASH google: $@"); }
		} # sub
	);
}

sub _google_search {
	# perform google search and return array of matched items as strings of title: link
	my ($self, $value) = @_;
	my $items = [];
	
	my $url = 'http://www.google.com/uds/GwebSearch?callback=receive_google_search_results&context=0&lstkp=0&rsz=large&hl=en&source=gsc&gss=.com&sig=&q='.uri_escape($value).'&key=notsupplied&v=1.0';
	$self->log_debug(9, "Fetching Google Search URL: $url");
	my $google = file_get_contents( $url );
	
	$self->log_debug(9, "Raw Google Response: $google");
	
	my $items = [];
	while ($google =~ s@\"titleNoFormatting\"\:"([^\"]+)\"@@) {
		my $title = $1;
		$title =~ s/(\\u([0-9a-f]{4}))/ chr(hex($2)); /iesg;
		$title =~ s/\\x(\w{2})/\%$1/g;
		$title = uri_unescape( $title );
		$title = decode_entities( $title );
		
		if (!($google =~ s@\"unescapedUrl\"\:\"([^\"]+)\"@@)) { last; }
		my $link = $1;
		$link =~ s/(\\u([0-9a-f]{4}))/ chr(hex($2)); /iesg;
		
		push @$items, { title => $title, link => $link };
	}
	
	return $items;
}

sub _google_image_search {
	# perform google image search and return array of matched items
	my ($self, $value) = @_;
	my $items = [];
	
	my $url = 'http://www.google.com/uds/GimageSearch?callback=google.search.ImageSearch.RawCompletion&rsz=small&hl=en&gss=.com&sig=&q=' . 
		uri_escape($value) . '&imgsz=small%7Cmedium%7Clarge%7Cxlarge&context=0&key=notsupplied&v=1.0';
		
	$self->log_debug(9, "Fetching Google Image Search URL: $url");
	my $google = file_get_contents( $url );
	
	$self->log_debug(9, "Raw Google Image Response: $google");
	
	my $items = [];
	while ($google =~ s@\"titleNoFormatting\"\:"([^\"]+)\"@@) {
		my $title = $1;
		$title =~ s/(\\u([0-9a-f]{4}))/ chr(hex($2)); /iesg;
		$title =~ s/\\x(\w{2})/\%$1/g;
		$title = uri_unescape( $title );
		$title = decode_entities( $title );
		
		if (!($google =~ s@\"unescapedUrl\"\:\"([^\"]+)\"@@)) { last; }
		my $link = $1;
		$link =~ s/(\\u([0-9a-f]{4}))/ chr(hex($2)); /iesg;
		
		push @$items, { title => $title, link => $link };
	}
	
	if (!@$items && ($google =~ /rate exceeded/)) {
		return undef;
	}
	
	return $items;
}

sub define {
	# define term using unofficial google api
	my ($self, $value, $args) = @_;
	
	return unless $value;
	
	$self->log_debug(9, "Forking for Define APIs...");
	
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		handler => '_fork_utf8_said',
		run => sub {
			eval {
				my $response = '';
				
				if (!$response) {
					# Try google to get exact wikipedia article name (case sensitive)
					my $items = $self->_google_search($value . " site:wikipedia.org");
					if ($items && $items->[0] && ($items->[0]->{link} =~ m@wikipedia.org/wiki/(.+)$@)) {
						my $wiki_article_title = uri_unescape($1);
						my $wiki_url = $items->[0]->{link};
						
						my $url = 'http://en.wikipedia.org/w/api.php?format=json&action=query&titles='.uri_escape($wiki_article_title).'&prop=extracts&exchars=512&exsectionformat=plain&explaintext=1';
						$self->log_debug(9, "Fetching URL: $url");
						my $wiki_raw = file_get_contents( $url );
						my $wiki_json = eval { json_parse( $wiki_raw ); };
						
						if ($wiki_json && $wiki_json->{query}->{pages}) {
							my $page_key = first_key( $wiki_json->{query}->{pages} );
							if ($wiki_json->{query}->{pages}->{$page_key}->{extract}) {
								my $extract = $wiki_json->{query}->{pages}->{$page_key}->{extract};
								my $nice_title = $wiki_article_title; $nice_title =~ s/_/ /g;
								
								# only prefix with title if extract doesn't already start with it
								my $nice_title_esc = $nice_title; $nice_title_esc =~ s/(\W)/\\$1/g;
								if ($extract !~ /^$nice_title_esc/) {
									$response .= "$nice_title: ";
								}
								
								# add extract
								$response .= "$extract";
								
								# only one sentence needed
								my $new_response = '';
								foreach my $sentence (split(/\.\s*/, $response)) {
									$new_response .= $sentence . ". ";
									last if (length($new_response) >= 50);
								}
								$response = trim($new_response);
								
								# squeeze URL onto end
								if (length($response) >= 500 - length($wiki_url)) {
									$response = substr($response, 0, 500 - length($wiki_url));
									$response =~ s/\.+$//; $response .= "...";
								}
								$response .= " " . $wiki_url;
							} # found definition
						} # good json
					} # first google result is a wiki
				} # need google / wiki search
				
				# No response?  Try dictionaryapi.com too, if we have an API key
				if (!$response && $self->{config}->{DictAPIKey} && ($value =~ /^\w+$/)) {
					my $url = 'http://www.dictionaryapi.com/api/v1/references/collegiate/xml/'.lc($value).'?key=' . $self->{config}->{DictAPIKey};
					$self->log_debug(9, "Fetching URL: $url");
					my $dict_raw = file_get_contents( $url );
					
					if ($dict_raw =~ m@<dt>(.+?)</dt>@s) {
						my $def_raw = $1; $def_raw =~ s/<.+?>//sg; $def_raw =~ s/^\W+//;
						$response .= ucfirst($value);
						if ($dict_raw =~ m@<fl>(.+?)</fl>@) { $response .= " ($1)"; }
						$response .= ": " . ucfirst($def_raw);
						$response = trim($response);
						if ($response !~ /\W$/) { $response .= "."; }
					}
				}
				
				if ($response) {
					print encode('UTF-8', $response, Encode::FB_QUIET) . "\n";
				}
				else {
					my $items = $self->_google_search($value);
					if (@$items) {
						my $item = shift @$items;
						my $meaning = $item->{title} . ": " . $item->{link};
						print "No definition found for $value, but a Google search finds: " . encode('UTF-8', $meaning, Encode::FB_QUIET) . "\n";
					}
					else {
						print "No definition found for: $value\n";
					}
				}
			}; # eval
			if ($@) { $self->log_debug(1, "CHILD CRASH define: $@"); }
		} # sub
	);
}

sub first_key {
	my $hashref = shift;
	my ($key, undef) = each %$hashref;
	return $key;
}

1;
