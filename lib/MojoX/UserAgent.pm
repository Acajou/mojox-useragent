package MojoX::UserAgent;

use warnings;
use strict;

use base 'Mojo::Base';

# No imports to make subclassing a bit easier
require Carp;

use Mojo::URL;
use Mojo::Transaction;
use Mojo::Pipeline;
use Mojo::Client;
use Mojo::Cookie;

__PACKAGE__->attr('redirect_limit', default => 10);
__PACKAGE__->attr('_client', default => sub { Mojo::Client->new });
# __PACKAGE__->attr('_handler', default => undefined);

sub new {
    my $self = shift->SUPER::new();

}

sub spool {
    my $self = shift;

}

sub run {
    my $self = shift;


}

sub crank {
    my $self = shift;

}

sub handler {
    my $self = shift;
    # Carp::croak('No callback registered') unless _handler;
    # $self->_handler;
}

sub register_callback {
    my $self = shift;

}

1;
