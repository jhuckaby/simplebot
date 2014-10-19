package SimpleBot::Plugin::Net;

##
# Net.pm
# SimpleBot Plugin
# Various network utility commands.
#
# !ping HOST
# !host HOST
# !head URL
# !telnet HOST PORT
##

use strict;
use base qw( SimpleBot::Plugin );
use Time::HiRes qw/time/;
use Net::Ping;
use Net::Ping::External;
use IO::Socket::INET;
use Tools;

sub init {
	my $self = shift;
	$self->register_commands('ping', 'dns', 'host', 'head', 'whead', 'http', 'sniff', 'url', 'wget', 'tcp', 'connect', 'telnet');
}

sub ping {
	# ping host
	my ($self, $host, $args) = @_;
	my $username = lc($args->{who});
	my $chan = nch($args->{channel});
	
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		who => $args->{who_disp},
		run => sub {
			eval {
				my $p = Net::Ping->new("external");
				$p->hires();
				my ($ret, $duration, $ip) = $p->ping($host, 1.0);
				if ($ret) {
					print sprintf("$host ($ip) is online (ping time: %.2f ms)\n", 1000 * $duration) . "\n";
				}
				else {
					print "Ping failed, $host is offline.\n";
				}
			}; # eval
			if ($@) {
				my $error_msg = $@;
				$self->log_debug(2, "Ping Error: $error_msg");
				print "$username: Ping Error: $error_msg\n";
			}
		} # sub
	);
	
	return undef;
}

sub dns {
	# convert host to ip
	my ($self, $host, $args) = @_;
	my $username = lc($args->{who});
	my $chan = nch($args->{channel});
	
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		who => $args->{who_disp},
		run => sub {
			eval {
				my @ips = ();
				if ($host =~ /^\d+\.\d+\.\d+\.\d+$/) {
					# reverse ip-to-host
					@ips = ( ipv4_to_hostname($host) );
				}
				else {
					# host-to-ip
					@ips = hostname_to_ipv4($host);
				}
				
				if (@ips && ($ips[0] =~ /\S/)) {
					print "$host resolved to: " . join(', ', @ips) . "\n";
				}
				else {
					print "DNS ERROR: $host could not be resolved.\n";
				}
			}; # eval
			if ($@) {
				my $error_msg = $@;
				$self->log_debug(2, "DNS Error: $error_msg");
				print "$username: DNS Error: $error_msg\n";
			}
		} # sub
	);
	
	return undef;
}
sub host { return dns(@_); }

sub head {
	# sniff url and return response status line and http headers
	my ($self, $url, $args) = @_;
	my $username = lc($args->{who});
	my $chan = nch($args->{channel});
	
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		who => $args->{who_disp},
		run => sub {
			eval {
				my $ua = LWP::UserAgent->new();
				$ua->timeout( 5 );
				$ua->agent( "Mozilla/5.0 (SimpleBot 1.0 URL Tester)" );
				
				my $response = $ua->request( HTTP::Request->new( 'HEAD', $url ) );
				
				my $output = $response->as_string();
				$output =~ s/\bClient\-[\w\-]+\:\s+[^\n]+//g; # strip useless "client" headers
				
				print trim($output) . "\n";
			}; # eval
			if ($@) {
				my $error_msg = $@;
				$self->log_debug(2, "Network Error: $error_msg");
				print "$username: Network Error: $error_msg\n";
			}
		} # sub
	);
	
	return undef;
}
sub whead { return head(@_); }
sub http { return head(@_); }
sub sniff { return head(@_); }
sub url { return head(@_); }
sub wget { return head(@_); }

sub tcp {
	# try tcp connect on host/ip and port
	my ($self, $value, $args) = @_;
	my $username = lc($args->{who});
	my $chan = nch($args->{channel});
	
	$self->{bot}->forkit(
		channel => nch( $args->{channel} ),
		who => $args->{who_disp},
		run => sub {
			eval {
				if ($value =~ /^([\w\-\.]+)\D+(\d+)/) {
					my ($host, $port) = ($1, $2);
					my $socket = undef;
					my $time_start = time();
					
					local $SIG{ALRM} = sub { die "ALRM\n" };
					alarm 5;
					eval {
						$socket = new IO::Socket::INET(
							PeerAddr => $host,
							PeerPort => $port,
							Proto => "tcp",
							Type => SOCK_STREAM,
							Timeout => 5
						);
					};
					alarm 0;
					if ($socket) {
						my $elapsed = sprintf("%.2f ms", (time() - $time_start) * 1000);
						print "TCP connection to $host:$port succeeded (time: $elapsed).\n";
					}
					else {
						my $error_msg = $@ ? "Timeout" : $!;
						print "ERROR: Could not open TCP socket to $host:$port: $error_msg\n";
					}
				}
			}; # eval
			if ($@) {
				my $error_msg = $@;
				$self->log_debug(2, "Ping Error: $error_msg");
				print "$username: Ping Error: $error_msg\n";
			}
		} # sub
	);
	
	return undef;
}
sub connect { return tcp(@_); }
sub telnet { return tcp(@_); }

1;
