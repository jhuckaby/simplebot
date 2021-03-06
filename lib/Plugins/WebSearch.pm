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
	$self->register_commands('google', 'define', 'image', 'stock', 'btc', 'bitcoin', 'urban', 'spell', 'reddit', 'r', 'rotten', 'movie', 'synopsis', 'plot', 'cast', 'beer', 'news', 'xkcd');
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
	
	if (!$self->{config}->{GoogleAPIKey}) {
		return "$username: You must set the WebSearch/GoogleAPIKey configuration parameter before using Google Image Search.";
	}
	if (!$self->{config}->{GoogleAppID}) {
		return "$username: You must set the WebSearch/GoogleAppID configuration parameter before using Google Image Search.";
	}
	
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
	
	# safe mode
	my $safety = 'high';
	if ($value =~ s/^unsafe\s+(.+)$/$1/i) {
		$safety = 'off';
	}
	
	my $url = 'https://www.googleapis.com/customsearch/v1?key=' . $self->{config}->{GoogleAPIKey} . '&cx=' . $self->{config}->{GoogleAppID} . '&safe=' . $safety . '&num=5&searchType=image&imgType=photo&q=' . uri_escape($value);
	
	$self->log_debug(9, "Fetching Google Image Search URL: $url");
	my $google = file_get_contents( $url );
	
	$self->log_debug(9, "Raw Google Image Response: $google");
	
	my $json = json_parse( $google ) || {};
	
	if ($json->{items}) {
		foreach my $item (@{$json->{items}}) {
			my $title = $item->{title} || '';
			my $link = $item->{link} || '';
			if ($link =~ /\.(jpg|jpeg|gif|png)(\?|$)/i) {
				push @$items, { title => $title, link => $link };
			}
		}
	}
	elsif ($json->{error}) {
		$self->log_debug(4, "Google Image API Error: " . $json->{error}->{code} . ": " . $json->{error}->{message});
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
				
				# No response?  Try dictionaryapi.com, if we have an API key
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
									foreach my $sentence (split(/\.\s+/, $response)) {
										$new_response .= $sentence . ". ";
										last if (length($new_response) >= 100);
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
				my $url = 'http://www.dictionaryapi.com/api/v1/references/collegiate/xml/'.lc(uri_escape($value)).'?key=' . $self->{config}->{DictAPIKey};
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

sub btc {
	# Check Bitcoin price via bitstamp.net free API
	my ($self, $value, $args) = @_;
	
	$self->log_debug(9, "Forking for BitStamp API...");
	
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		handler => '_fork_utf8_said',
		run => sub {
			eval {
				# http://www.bitstamp.net/api/ticker/
				# {"high": "395.00", "last": "390.00", "timestamp": "1413659163", "bid": "389.90", "vwap": "386.0", "volume": "7847.64414815", "low": "377.00", "ask": "390.00"}
				
				my $url = 'http://www.bitstamp.net/api/ticker/';
				$self->log_debug(9, "Fetching BitStamp URL: $url");
				
				my $json_raw = trim(file_get_contents($url));
				$self->log_debug(9, "Raw result: $json_raw");
				
				my $json = eval { json_parse( $json_raw ); };
				if ($json && $json->{last}) {
					print "Bitcoin price is currently: \$" . $json->{last} . " USD for 1 BTC.\n";
				}
				else {
					print "ERROR: Could not determine Bitcoin price (is BitStamp.net down?)\n";
				}
			}; # eval
			if ($@) { $self->log_debug(1, "CHILD CRASH btc: $@"); }
		} # sub
	);
}
sub bitcoin { btc(@_); }

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
					
					# filter bad words if desired
					if ($self->{config}->{UrbanBadWordFilter}) {
						my $regexp = $self->{bot}->{bad_word_match};
						$response =~ s@$regexp@****@ig;
					}
					
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

sub reddit {
	# random imgur image from front page of subreddit
	my ($self, $value, $args) = @_;
	my $username = $args->{who};
	
	return undef unless $value;
	
	$self->log_debug(9, "Forking for Reddit API...");
	
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		handler => '_fork_utf8_said',
		run => sub {
			eval {
				# http://www.reddit.com/r/aww.json
				my $image_url = '';
				my $url = 'http://www.reddit.com/r/'.$value.'.json';
				$self->log_debug(9, "Fetching Reddit URL: $url");
				
				my $json_raw = trim(file_get_contents($url));
				# $self->log_debug(9, "Raw result: $json_raw");
				
				my $json = eval { json_parse( $json_raw ); };
				if ($json && $json->{data} && $json->{data}->{children}) {
					my $urls = [];
					foreach my $child (@{$json->{data}->{children}}) {
						if (($child->{data}->{domain} !~ /self/i) && ($child->{data}->{url} !~ m@/a/@)) {
							push @$urls, $child->{data}->{url};
						}
					}
					$self->log_debug(9, "URLs: " . json_compose($urls));
					$image_url = rand_array($urls);
					$self->log_debug(9, "Chosen image: $image_url");
				}
				
				if ($image_url) {
					$image_url =~ s@^(\w+\:\/\/)(imgur.com)/(\w+)$@ $1 . 'i.imgur.com/' . $3 . '.jpg'; @e;
					print "$image_url\n";
				}
				else {
					print "No images found in subreddit: /r/$value\n";
				}
			}; # eval
			if ($@) { $self->log_debug(1, "CHILD CRASH reddit: $@"); }
		} # sub
	);
}
sub r { return reddit(@_); }

sub rotten {
	# get movie info from rotten tomatoes (requires free API Key)
	my ($self, $value, $args) = @_;
	my $username = $args->{who};
	
	return undef unless $value;
	
	if (!$self->{config}->{RottenAPIKey}) {
		return "$username: No API key is set for RottenTomatoes.com.  Please type: !help rotten";
	}
	
	$self->log_debug(9, "Forking for Rotten Tomatoes API...");
	
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		handler => '_fork_utf8_said',
		run => sub {
			eval {
				# http://api.rottentomatoes.com/api/public/v1.0/movies.json?apikey=...&q=Toy+Story+3&page_limit=1
				
				my $url = 'http://api.rottentomatoes.com/api/public/v1.0/movies.json?apikey='.$self->{config}->{RottenAPIKey}.'&q='.uri_escape($value).'&page_limit=1';
				$self->log_debug(9, "Fetching Rotten URL: $url");
				
				my $json_raw = trim(file_get_contents($url));
				$self->log_debug(9, "Raw result: $json_raw");
				
				my $json = eval { json_parse( $json_raw ); };
				if ($json && $json->{movies}) {
					my $movie = $json->{movies}->[0];
					my $resp = '';
					
					$resp .= $movie->{title} . " (" . $movie->{year} . ", Rated " . $movie->{mpaa_rating} . ")";
					if ($args->{synopsis}) {
						$resp .= ": " . $movie->{synopsis};
					}
					elsif ($args->{cast}) {
						my $members = [];
						foreach my $member (@{$movie->{abridged_cast}}) {
							push @$members, $member->{name};
						}
						$resp .= ": " . join(', ', @$members);
					}
					else {
						$resp .= ": Critics Score: " . $movie->{ratings}->{critics_score} . '%';
						$resp .= ", Audience Score: " . $movie->{ratings}->{audience_score} . '%';
					}
					
					print "$resp\n";
				}
				else {
					print "No movie found for: $value\n";
				}
			}; # eval
			if ($@) { $self->log_debug(1, "CHILD CRASH rotten: $@"); }
		} # sub
	);
}
sub movie { return rotten(@_); }

sub synopsis {
	# get movie synopsis
	my ($self, $value, $args) = @_;
	$args->{synopsis} = 1;
	return $self->rotten( $value, $args );
}
sub plot { return synopsis(@_); }

sub cast {
	# get movie cast
	my ($self, $value, $args) = @_;
	$args->{cast} = 1;
	return $self->rotten( $value, $args );
}

sub beer {
	# get beer info from BreweryDB.com (requires free API Key)
	my ($self, $value, $args) = @_;
	my $username = $args->{who};
	
	return undef unless $value;
	
	if (!$self->{config}->{BeerAPIKey}) {
		return "$username: No API key is set for BreweryDB.com.  Please type: !help beer";
	}
	
	$self->log_debug(9, "Forking for BreweryDB API...");
	
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		handler => '_fork_utf8_said',
		run => sub {
			eval {
				# http://api.brewerydb.com/v2/search?key=...&type=beer&withBreweries=Y&q=pliny
				
				my $url = 'http://api.brewerydb.com/v2/search?key='.$self->{config}->{BeerAPIKey}.'&type=beer&withBreweries=Y&q='.uri_escape($value);
				$self->log_debug(9, "Fetching BreweryDB URL: $url");
				
				my $json_raw = trim(file_get_contents($url));
				$self->log_debug(9, "Raw result: $json_raw");
				
				my $json = eval { json_parse( $json_raw ); };
				if ($json && $json->{data}) {
					my $beer = $json->{data}->[0];
					my $resp = '';
					
					$resp .= $beer->{name};
					if ($beer->{style}->{name}) { $resp .= " (" . $beer->{style}->{name} . ")"; }
					
					my $parts = [];
					if ($beer->{abv}) { push @$parts, 'ABV: ' . $beer->{abv} . '%'; }
					if ($beer->{ibu}) { push @$parts, 'IBU: ' . $beer->{ibu} . 'ppm'; }
					
					if (scalar @$parts) {
						$resp .= ": " . join(', ', @$parts) . "\n";
					}
					
					if ($beer->{breweries}) {
						my $brewery = $beer->{breweries}->[0];
						$resp .= $brewery->{name};
						if ($brewery->{website}) { $resp .= " - " . $brewery->{website}; }
						$resp .= "\n";
					}
					
					if ($beer->{description}) {
						$resp .= $beer->{description} . "\n";
					}
					
					print trim($resp) . "\n";
				}
				else {
					print "No beer found for: $value\n";
				}
			}; # eval
			if ($@) { $self->log_debug(1, "CHILD CRASH beer: $@"); }
		} # sub
	);
}

sub news {
	# get random news article from Google News
	my ($self, $value, $args) = @_;
	my $username = $args->{who};
	
	return undef unless $value;
	
	$self->log_debug(9, "Forking for Google News API...");
	
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		handler => '_fork_utf8_said',
		run => sub {
			eval {
				# http://ajax.googleapis.com/ajax/services/search/news?v=1.0&rsz=5&q=minecraft
				
				my $url = 'http://ajax.googleapis.com/ajax/services/search/news?v=1.0&rsz=5&q='.uri_escape($value);
				$self->log_debug(9, "Fetching Google News URL: $url");
				
				my $json_raw = trim(file_get_contents($url));
				$self->log_debug(9, "Raw result: $json_raw");
				
				my $json = eval { json_parse( $json_raw ); };
				if ($json && $json->{responseData} && $json->{responseData}->{results}) {
					my $article = rand_array( $json->{responseData}->{results} );
					my $resp = '';
					
					$article->{titleNoFormatting} =~ s/\&\#(\d+)\;/ chr($1); /eg;
					
					$resp .= $article->{publisher} . ": ";
					$resp .= $article->{titleNoFormatting} . ": ";
					$resp .= $article->{unescapedUrl} . "\n";
					
					my $body = $article->{content};
					$body =~ s/<.+?>//sg; 
					$body =~ s/\&\#(\d+)\;/ chr($1); /eg;
					$body =~ s/\&\#?\w+\;//g;
					$resp .= $body;
					
					print trim($resp) . "\n";
				}
				else {
					print "No news found for: $value\n";
				}
			}; # eval
			if ($@) { $self->log_debug(1, "CHILD CRASH news: $@"); }
		} # sub
	);
}

sub xkcd {
	# get latest xkcd comic
	my ($self, $value, $args) = @_;
	my $username = $args->{who};
		
	$self->log_debug(9, "Forking for XKCD API...");
	
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		handler => '_fork_utf8_said',
		run => sub {
			eval {
				# http://xkcd.com/info.0.json
				
				my $url = 'http://xkcd.com/info.0.json';
				$self->log_debug(9, "Fetching XKCD URL: $url");
				
				my $json_raw = trim(file_get_contents($url));
				$self->log_debug(9, "Raw result: $json_raw");
				
				my $json = eval { json_parse( $json_raw ); };
				if ($json && $json->{img}) {
					my $resp = '';
					
					$resp .= $json->{title} . ": ";
					$resp .= $json->{img};
					
					print trim($resp) . "\n";
				}
				else {
					print "No xkcd comic found!\n";
				}
			}; # eval
			if ($@) { $self->log_debug(1, "CHILD CRASH xkcd: $@"); }
		} # sub
	);
}

1;
