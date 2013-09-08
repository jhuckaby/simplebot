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
use List::Util qw(shuffle);

sub init {
	my $self = shift;
	$self->register_commands('insult');
	
	$self->{intros} = [ split(/\,\s*/, trim($self->{config}->{Intros})) ];
	$self->{adjectives} = [ map { $_ =~ s/\|/ /g; $_; } split(/\s+/, trim($self->{config}->{Adjectives})) ];
	$self->{amounts} = [ map { $_ =~ s/\|/ /g; $_; } split(/\s+/, trim($self->{config}->{Amounts})) ];
	$self->{nouns} = [ map { $_ =~ s/\|/ /g; $_; } split(/\s+/, trim($self->{config}->{PluralThings})) ];
	$self->{things} = [ map { $_ =~ s/\|/ /g; $_; } split(/\s+/, trim($self->{config}->{SingleThings})) ];
	
	# remove dupes
	my $temp;
	$temp = { map { $_ => 1; } @{$self->{intros}} }; $self->{intros} = [ keys %$temp ];
	$temp = { map { $_ => 1; } @{$self->{adjectives}} }; $self->{adjectives} = [ keys %$temp ];
	$temp = { map { $_ => 1; } @{$self->{amounts}} }; $self->{amounts} = [ keys %$temp ];
	$temp = { map { $_ => 1; } @{$self->{nouns}} }; $self->{nouns} = [ keys %$temp ];
	$temp = { map { $_ => 1; } @{$self->{things}} }; $self->{things} = [ keys %$temp ];
}

sub insult {
	# insult generator
	my ($self, $msg, $args) = @_;
	my $username = $args->{who};
	my $chan = $args->{channel};
	
	# no username set?  insult self
	if (!$msg) { $msg = $username; }
	
	# allow user to specify replacement words
	my $extras = [];
	$msg =~ s/\s+(\S+)/ push @$extras, $1; ''; /eg;
	
	my $extra_adjs = [];
	my $extra_noun = '';
	foreach my $extra (@$extras) {
		if ($extra =~ /\W$/) { $extra_noun = $extra; $extra_noun =~ s/\W+$//; }
		else { push @$extra_adjs, $extra; }
	}
	my $enoun_is_plural = $extra_noun =~ m/s\W*$/i;
	
	# choose type of insult
	my $type = probably(0.5);
	if ($extra_noun && $enoun_is_plural) { $type = 0; }
	if ($extra_noun && !$enoun_is_plural) { $type = 1; }
	
	if ($type) {
		# type 1, singular insult
		my $num_adjs = int( rand() * 3 ) + 1;
		my $num_things = int( rand() * 2 ) + 1;
		
		# generate unique adjectives
		my $adjs_hash = {};
		while ((scalar keys %$adjs_hash) < $num_adjs) {
			my $adj = rand_array( $self->{adjectives} );
			$adjs_hash->{$adj} = 1;
		}
		my $adjs = [ shuffle( keys %$adjs_hash ) ];
		
		# apply user extras as replacements, if any
		my $idx = 0;
		foreach my $extra (@$extra_adjs) { $adjs->[$idx++] = $extra; }
		
		# generate unique nouns (things)
		my $things_hash = {};
		while ((scalar keys %$things_hash) < $num_things) {
			my $thing = rand_array( $self->{things} );
			$things_hash->{$thing} = 1;
		}
		my $things = [ shuffle( keys %$things_hash ) ];
		
		# user replacement noun
		if ($extra_noun) { $things->[-1] = $extra_noun; }
		
		# compile insult sentence
		my $intro = rand_array( $self->{intros} );
		my $insult = "$msg $intro";
		if ($adjs->[0] =~ /^[aeiou]/) { $insult .= 'n'; }
		
		$insult .= ' ' . join(', ', @$adjs) . ' ' . join(' ', @$things) . '!';
		return $insult;
	}
	else {
		# type 2, plural insult
		my $adj1 = rand_array( $self->{adjectives} );
		my $adj2 = rand_array( $self->{adjectives} );
		while ($adj2 eq $adj1) { $adj2 = rand_array( $self->{adjectives} ); }
		
		# user replacements
		if (@$extra_adjs > 0) { $adj1 = $extra_adjs->[0]; }
		if (@$extra_adjs > 1) { $adj2 = $extra_adjs->[1]; }
		
		# choose random parts
		my $intro = rand_array( $self->{intros} );
		my $amount = rand_array( $self->{amounts} );
		my $noun = $extra_noun || rand_array( $self->{nouns} );
		
		# compile insult sentence
		my $insult = "$msg $intro";
		if ($adj1 =~ /^[aeiou]/) { $insult .= 'n'; }
		
		$insult .= " $adj1 $amount of $adj2 $noun!";
		return $insult;
	}
}

1;
