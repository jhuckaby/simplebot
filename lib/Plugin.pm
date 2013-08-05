package SimpleBot::Plugin;

# base class for SimpleBot plugins

use strict;
use Data::Dumper;
use Tools;

sub new {
	my $class = shift;
	my $self = bless( {@_}, $class );
	
	$self->{name} = ''.$class;
		
	$self->{name} =~ s/^.+\:\:(\w+)\=.+$/$1/;
	$self->{name} =~ s/^.+\:\:(\w+).*$/$1/;
	
	return $self;
}

sub init {
	# override in subclass
}

sub handler {
	# override in subclass
	# generic handler for commands if no specific method defined
}

sub say {
	# proxy for bot say(), but log it too
	my $self = shift;
	my $args = (scalar @_ == 1) ? $_[0] : {@_};
	
	$self->log_debug(6, "Saying: " . Dumper($args));
	foreach my $line (split(/\n/, $args->{body})) {
		if ($line =~ /\S/) {
			$args->{body} = $line;
			$self->{bot}->say( $args );
		}
	}
}
sub emote {
	# proxy for bot emote(), but log it too
	my $self = shift;
	my $args = (scalar @_ == 1) ? $_[0] : {@_};
	
	$self->log_debug(6, "Emoting: " . Dumper($args));
	foreach my $line (split(/\n/, $args->{body})) {
		if ($line =~ /\S/) {
			$args->{body} = $line;
			$self->{bot}->emote( $args );
		}
	}
}
sub notice {
	# proxy for bot notice(), but log it too
	my $self = shift;
	my $args = (scalar @_ == 1) ? $_[0] : {@_};
	
	$self->log_debug(6, "Posting Notice: " . Dumper($args));
	foreach my $line (split(/\n/, $args->{body})) {
		if ($line =~ /\S/) {
			$args->{body} = $line;
			$self->{bot}->notice( $args );
		}
	}
}

sub dirty {
	# set dirty flag in data, pass to bot
	my $self = shift;
	$self->{bot}->dirty( @_ );
}

sub enqueue_plugin_task {
	# enqueue task for parent fork to execute on plugin
	# designed to be called in child fork obviously
	my $self = shift;
	my $cmd = shift;
	my $args = shift || {};
	
	$args->{Type} = 'Plugin';
	$args->{Plugin} = $self->{name};
	$args->{Command} = $cmd;
	
	$self->{bot}->enqueue_task($args);
}

sub register_commands {
	# register one or more commands to activate plugin
	my $self = shift;
	
	my ($package, undef, undef) = caller();
	$package =~ s/^(.+)::(\w+)$/$2/;
	
	while (my $cmd = shift @_) {
		if (!$self->{bot}->{_eb_commands}->{$cmd}) {
			$self->log_debug(4, "Registering Plugin Command: $cmd --> $package");
			$self->{bot}->{_eb_commands}->{$cmd} = $self;
		}
	}
}

sub irc_cmd {
	# proxy to bot
	my $self = shift;
	return $self->{bot}->irc_cmd( @_ );
}

sub log_debug {
	# log debug message for plugin
	my ($self, $level, $msg) = @_;
	
	my ($package, undef, undef) = caller();
	$package =~ s/^(.+)::(\w+)$/$2/;
	
	$self->{bot}->log_debug($level, $msg, $package);
}

1;
