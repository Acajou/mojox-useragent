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
# __PACKAGE__->attr('_client', default => sub { Mojo::Client->new });
# __PACKAGE__->attr('_handler', default => undefined);

our $VERSION = '0.001';

sub new {
    my $self = shift->SUPER::new();
    $self->{_client} = Mojo::Client->new;
    return $self;
}

sub spool_tx {
    my $self = shift;
    my $new_transactions = [@_];
    for my $tx (@{$new_transactions}) {
        push @{$self->{_txs}}, $tx;
    }
}

sub run_all {
    my $self = shift;
    my @transactions = @{$self->{_txs}};

    print "Transactions: " . @transactions . "\n";
    while (1) {
        $self->{_client}->spin(@transactions);
        my @buffer;
        while (my $tx = shift @transactions) {
            if ($tx->is_finished) {
                # Callback
                print $tx->req->url . " done!\n";
            } else {
                push @buffer, $tx;
            }
        }
        push @transactions, @buffer;
        last unless @transactions;
    }
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
__END__
