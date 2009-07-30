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
__PACKAGE__->attr('_client',  default => sub { Mojo::Client->new });
__PACKAGE__->attr(
    'default_done_cb',
    default => sub {
        return sub {
            my ($self, $url, $tx) = @_;
            print "$url done.\n";
        };
    }
);

our $VERSION = '0.001';

sub new {
    my $self = shift->SUPER::new();
    # $self->{_client} = Mojo::Client->new;
    return $self;
}

sub spool_tx {
    my $self = shift;
    my $new_transactions = [@_];
    for my $tx (@{$new_transactions}) {
        # Kind of a hack to add new properties to a class I am told.
        # vti suggests decorator pattern, could subclass too
        # or build some data structure with $tx $hops and $original_url...
        $tx->{_hops} = 0 unless $tx->{_hops};
        $tx->{_original_url} = $tx->req->url unless $tx->{_original_url};
        $tx->{_done_cb} = $self->default_done_cb unless $tx->{_done_cb};
        push @{$self->{_txs}}, $tx;
    }
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
                && $tx->{_hops} < $self->redirect_limit
                && (my $location = $tx->res->headers->header('Location')))
            {

                # Presumably 304 (not modified) shouldn't include
                # a Location so shouldn't come in here...

                unless ($tx->res->code == 305) {
                    # should really clone here...
                    my $new_tx = Mojo::Transaction->new_get($location);
                    $new_tx->{_hops} = $tx->{_hops}+1;
                    $new_tx->{_original_url} = $tx->{_original_url};
                    $new_tx->{_done_cb} = $tx->{_done_cb};
                    $self->spool_tx($new_tx);
                }
                else {

                    # Set up a proxied request (TODO)
                }
            }
            else {

                # Callback (TODO)
                # print $tx->{_original_url} . " done!\n";
                # print "Hops: " . ($tx->{_hops} ? $tx->{_hops} : 0) . "\n";
                # print "Ended at: " . $tx->req->url . "\n";
                $tx->{_done_cb}->($self, $tx->{_original_url}, $tx);
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
