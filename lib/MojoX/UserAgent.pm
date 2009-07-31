package MojoX::UserAgent;

use warnings;
use strict;

use base 'Mojo::Base';

# No imports to make subclassing a bit easier
require Carp;

use Mojo::URL;
use Mojo::Pipeline;
use Mojo::Client;
use Mojo::Cookie;
use MojoX::UserAgent::Transaction;

__PACKAGE__->attr('redirect_limit', default => 10);
__PACKAGE__->attr('follow_redirects', default => 1);
# pipeline_method: 0 -> Don't Pipeline
#                  1 -> Pipeline Vertically
#                  2 -> Pipeline Horizontally
# (could even allow per-tx setting)
__PACKAGE__->attr('pipeline_method', default => 0);
__PACKAGE__->attr('maxconnections', default => 2);
__PACKAGE__->attr('maxpipereqs', default => 5);
__PACKAGE__->attr('_client',  default => sub { Mojo::Client->new });
__PACKAGE__->attr(
    'default_done_cb',
    default => sub {
        return sub {
            my ($self, $tx) = @_;
            my $url = $tx->hops ? $tx->original_req->url : $tx->req->url;
            print "$url done in " . $tx->hops . " hops.\n";
        };
    }
);

our $VERSION = '0.001';

sub new {
    my $self = shift->SUPER::new();
    # $self->{_client} = Mojo::Client->new;
    return $self;
}

sub spool_txs {
    my $self = shift;
    my $new_transactions = [@_];
    for my $tx (@{$new_transactions}) {
        push @{$self->{_txs}}, $tx;
    }
}

sub spool_get {
    my $self = shift;
    my $url = shift;
    my $tx = MojoX::UserAgent::Transaction->new(
        {   url      => $url,
            callback => $self->default_done_cb
        }
    );
    push @{$self->{_txs}}, $tx;
}

sub run_all {
    my $self = shift;

    while (1) {
        last unless $self->crank;
    }
}

sub crank {
    my $self = shift;
    my $transactions = $self->{_txs};
    $self->_client->spin(@{$transactions});
    my @buffer;
    while (my $tx = shift @{$transactions}) {
        if ($tx->is_finished) {
            if ($tx->res->is_status_class(300)
                && $self->follow_redirects
                && $tx->hops < $self->redirect_limit
                && (my $location = $tx->res->headers->header('Location')))
            {

                # Presumably 304 (not modified) shouldn't include
                # a Location so shouldn't come in here...

                unless ($tx->res->code == 305) {

                    # should really clone here...
                    my $new_tx = MojoX::UserAgent::Transaction->new(
                        {   url          => $location,
                            method       => $tx->req->method,
                            hops         => $tx->hops + 1,
                            callback     => $tx->done_cb,
                            original_req => (
                                  $tx->original_req
                                ? $tx->original_req
                                : $tx->req
                            )
                        }
                    );
                    $self->spool_txs($new_tx);
                }
                else {

                    # Set up a proxied request (TODO)
                }
            }
            else {
                $tx->done_cb->($self, $tx);
            }
        }
        else {
            push @buffer, $tx;
        }
    }
    push @{$transactions}, @buffer;
    return scalar @{$transactions};
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
__END__
