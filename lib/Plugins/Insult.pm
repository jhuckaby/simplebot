package SimpleBot::Plugin::Insult;

##
# Insult.pm
# SimpleBot Plugin
# Borrowed and modified from http://search.cpan.org/dist/Acme-Scurvy-Whoreson-BilgeRat-Backend-insultserver/
#
# !insult NICKNAME
##

use strict;
use base qw( SimpleBot::Plugin );
use Tools;

sub init {
	my $self = shift;
	$self->register_commands('insult');
	
	$self->{intros} = [ split(/\,\s*/, trim($self->{config}->{Intros})) ];
	$self->{adjectives} = [ map { $_ =~ s/\|/ /g; $_; } split(/\s+/, trim($self->{config}->{Adjectives})) ];
	$self->{amounts} = [ map { $_ =~ s/\|/ /g; $_; } split(/\s+/, trim($self->{config}->{Amounts})) ];
	$self->{nouns} = [ map { $_ =~ s/\|/ /g; $_; } split(/\s+/, trim($self->{config}->{Nouns})) ];
}

sub insult {
	# insult generator
	my ($self, $msg, $args) = @_;
	my $username = $args->{who};
	my $chan = $args->{channel};
	
	my $adj1 = rand_array( $self->{adjectives} );
	my $adj2 = rand_array( $self->{adjectives} );
	while ($adj2 eq $adj1) { $adj2 = rand_array( $self->{adjectives} ); }
	
	my $intro = rand_array( $self->{intros} );
	my $amount = rand_array( $self->{amounts} );
	my $noun = rand_array( $self->{nouns} );
	
	my $insult = "$msg $intro";
	if ($adj1 =~ /^[aeiou]/) { $insult .= 'n'; }
	
	$insult .= " $adj1 $amount of $adj2 $noun!";
	return $insult;
}

1;
