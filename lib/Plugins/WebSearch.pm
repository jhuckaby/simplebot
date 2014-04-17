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
	$self->register_commands('google', 'define', 'image', 'stock', 'urban', 'spell');
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
						$wiki_article_title =~ s/^Wiktionary\://;
						my $wiki_url = $items->[0]->{link};
						
						my $orig_words_pipe_esc = join('|', map { $_ =~ s/\W+//g; $_ =~ s/e?s$//i; $_; } split(/\s+/, $value));
						my $wiki_article_title_esc = $wiki_article_title; $wiki_article_title_esc =~ s/\W+//g;
						
						$self->log_debug(9, "orig_words_pipe_esc: $orig_words_pipe_esc (title_esc: $wiki_article_title_esc)");
						
						if (($wiki_article_title_esc =~ m@($orig_words_pipe_esc)@i) && ($wiki_article_title !~ /\:/)) {
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
									if ($extract !~ /^(the\s+|a\s+)?$nice_title_esc/i) {
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
						} # good wiki title
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

sub spell {
	# Spell check from DictionaryAPI.com
	my ($self, $value, $args) = @_;
	my $username = $args->{who};
	
	return undef unless $value;
	
	if (!$self->{config}->{DictAPIKey}) {
		return "$username: No API key is set for DictionaryAPI.com.  Please type: !help spell";
	}
	
	$self->log_debug(9, "Forking for DictionaryAPI.com...");
	
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		handler => '_fork_utf8_said',
		run => sub {
			eval {
				my $url = 'http://www.dictionaryapi.com/api/v1/references/collegiate/xml/'.lc($value).'?key=' . $self->{config}->{DictAPIKey};
				$self->log_debug(9, "Fetching URL: $url");
				my $dict_raw = file_get_contents( $url );
				my $response = '';
				
				if ($dict_raw =~ m@<dt>(.+?)</dt>@s) {
					my $def_raw = $1; $def_raw =~ s/<.+?>//sg; $def_raw =~ s/^\W+//;
					$response .= ucfirst($value) . " is spelled correctly.\n";
				}
				else {
					my $xml = parse_xml( $dict_raw );
					$response .= ucfirst($value) . " was not found in the dictionary.";
					if (ref($xml) && $xml->{suggestion}) {
						XMLalwaysarray( xml=>$xml, element=>'suggestion' );
						my $suggestions = $xml->{suggestion};
						while (scalar @$suggestions > 5) { pop @$suggestions; }
						$response .= "  Suggestions: " . join(', ', @$suggestions);
					}
				}
				
				print "$response\n";
			}; # eval
			if ($@) { $self->log_debug(1, "CHILD CRASH spell: $@"); }
		} # sub
	);
}

sub stock {
	# Yahoo! stock symbol lookup (get quote)
	my ($self, $value, $args) = @_;
	my $username = $args->{who};
	
	return undef unless $value;
	
	$self->log_debug(9, "Forking for Yahoo Stock API...");
	
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		handler => '_fork_utf8_said',
		run => sub {
			eval {
				# http://download.finance.yahoo.com/d/quotes.csv?s=adp&f=l1=.csv
				# 75.82,"ADP","ADP","-1.55 - -2.00%","ADP",2023253
				# 0.00,"ZRZ","ZRZ","N/A - N/A","ZRZ",N/A
				
				my $url = 'http://download.finance.yahoo.com/d/quotes.csv?s='.$value.'&f=l1=.csv';
				$self->log_debug(9, "Fetching Yahoo Stock URL: $url");
				
				my $csv_raw = trim(file_get_contents($url));
				$self->log_debug(9, "Raw result: $csv_raw");
				
				my $cols = [ map { $_ =~ s/^\"(.+)\"$/$1/; $_; } split(/\,/, $csv_raw) ];
				if ($cols->[0] !~ /^0(\.0+)?$/) {
					# non-zero value
					my $price = '$' . $cols->[0];
					my $symbol = uc($cols->[1]);
					my ($price_change, $pct_change) = split(/\s+\-\s+/, $cols->[3]);
					print "$symbol: $price ($price_change, $pct_change)\n";
				}
				else {
					print "Stock symbol not found: ".uc($value)."\n";
				}
			}; # eval
			if ($@) { $self->log_debug(1, "CHILD CRASH stock: $@"); }
		} # sub
	);
}

sub urban {
	# Urban Dictionary term search
	my ($self, $value, $args) = @_;
	my $username = $args->{who};
	
	return undef unless $value;
	
	$self->log_debug(9, "Forking for Urban Dictionary API...");
	
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		handler => '_fork_utf8_said',
		run => sub {
			eval {
				# http://api.urbandictionary.com/v0/define?page=1&term=pumpion
				
				my $url = 'http://api.urbandictionary.com/v0/define?page=1&term='.uri_escape($value);
				$self->log_debug(9, "Fetching Urban Dictionary URL: $url");
				
				my $json_raw = trim(file_get_contents($url));
				$self->log_debug(9, "Raw result: $json_raw");
				
				my $json = eval { json_parse( $json_raw ); };
				if ($json && $json->{list} && $json->{list}->[0] && $json->{list}->[0]->{definition}) {
					my $item = $json->{list}->[0];
					# my $urban_url = $item->{permalink};
					my $urban_url = 'http://www.urbandictionary.com/define.php?term=' . uri_escape($value);
					my $title = ucfirst($item->{word} || $value);
					my $definition = $item->{definition};
					my $response = "$title: $definition";
					
					# only one sentence needed
					my $new_response = '';
					foreach my $sentence (split(/\.\s*/, $response)) {
						$new_response .= $sentence . ". ";
						last if (length($new_response) >= 50);
					}
					$response = trim($new_response);
					
					# squeeze URL onto end
					if (length($response) >= 500 - length($urban_url)) {
						$response = substr($response, 0, 500 - length($urban_url));
						$response =~ s/\.+$//; $response .= "...";
					}
					$response .= " " . $urban_url;
					
					print "$response\n";
				}
				else {
					print "Definition not found: ".ucfirst($value)."\n";
				}
			}; # eval
			if ($@) { $self->log_debug(1, "CHILD CRASH urban: $@"); }
		} # sub
	);
}

1;
