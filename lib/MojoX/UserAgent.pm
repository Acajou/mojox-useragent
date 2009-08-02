package MojoX::UserAgent;

use warnings;
use strict;

use base 'Mojo::Base';

use Carp 'croak';

use Mojo::URL;
use Mojo::Pipeline;
use Mojo::Client;
use Mojo::Cookie;
use MojoX::UserAgent::Transaction;
use MojoX::UserAgent::CookieJar;

__PACKAGE__->attr('redirect_limit', default => 10);
__PACKAGE__->attr('follow_redirects', default => 1);

# pipeline_method: 0 -> Don't Pipeline
#                  1 -> Pipeline Vertically
#                  2 -> Pipeline Horizontally
# (could even allow per-tx setting)
__PACKAGE__->attr('pipeline_method', default => 0);

__PACKAGE__->attr('maxconnections', default => 2);
__PACKAGE__->attr('maxpipereqs', default => 5);


__PACKAGE__->attr('_tx_count', default => 0);
__PACKAGE__->attr('_client',  default => sub { Mojo::Client->new });
__PACKAGE__->attr('cookie_jar',
    default => sub { MojoX::UserAgent::CookieJar->new });

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
        # Fixup (TODO) 
        push @{$self->{_txs}}, $tx;
    }
}

sub get {
    my $self = shift;
    my $url = shift;
    my $cb = shift || $self->default_done_cb;

    my $tx = MojoX::UserAgent::Transaction->new(
        {   url      => $url,
            callback => $cb
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

            $self->{_tx_count}++;

            # Check for Cookies:
            $self->extract_cookies($tx);

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
                     croak('Proxy support not yet implemented');
                }
            }
            else {

                # Invoke Callback
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

sub extract_cookies {
    my ($self, $tx) = @_;

    my @cookies;
    my $cookie_header;

    if ( $cookie_header = $tx->res->headers->set_cookie) {
        my $coref =  Mojo::Cookie::Response->parse($cookie_header);
        push @cookies, @{$coref};
    }
    if ( $cookie_header = $tx->res->headers->set_cookie2) {
        my $coref =  Mojo::Cookie::Response->parse($cookie_header);
        push @cookies, @{$coref};
    }


    if (@cookies) {
        my @cleared = $self->scrub_cookies($tx, @cookies);
        $self->cookie_jar->store(@cleared) if @cleared;
    }


    1;
}

sub scrub_cookies {
    my $self = shift;
    my $tx = shift;

    my @cookies = @_;
    my @cleared;

    for my $cookie (@cookies) {

        # Domain check
        unless ($cookie->domain) {
            $cookie->domain($tx->req->url->host);
        }
        else {
            # TODO: check that domain value matches request url;
        }

        # Port check
        if ($cookie->port) {
            # TODO: should be comma separated list of numbers
        }
        push @cleared, $cookie;
    }
    return @cleared;
}

1;
__END__
