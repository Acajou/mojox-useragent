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

our $VERSION = '0.001';

__PACKAGE__->attr('redirect_limit', default => 10);
__PACKAGE__->attr('follow_redirects', default => 1);

# pipeline_method: 0 -> Don't Pipeline
#                  1 -> Pipeline Vertically (coming soon)
#                  2 -> Pipeline Horizontally (coming soon)
__PACKAGE__->attr('pipeline_method', default => 0);

__PACKAGE__->attr('maxconnections', default => 5); # coming soon
__PACKAGE__->attr('maxpipereqs', default => 5); # coming soon

__PACKAGE__->attr('validate_cookie_paths', default => 0);

__PACKAGE__->attr('cookie_jar',
    default => sub { MojoX::UserAgent::CookieJar->new });

__PACKAGE__->attr('agent',
    default => "Mozilla/5.0 (compatible; MojoX::UserAgent/$VERSION)");

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

__PACKAGE__->attr('_count', default => 0);

__PACKAGE__->attr('_client',  default => sub { Mojo::Client->new });

__PACKAGE__->attr('_active',  default => sub { {} });
__PACKAGE__->attr('_ondeck',  default => sub { {} });


__PACKAGE__->attr('app');

sub new {
    my $self = shift->SUPER::new();
    $self->_client->keep_alive_timeout(30);
    return $self;
}

sub cookies_for_url {
    my $self = shift;

    my $resp_cookies = $self->cookie_jar->cookies_for_url(@_);

    return [] unless @{$resp_cookies};

    # now make request cookies
    my @req_cookies = ();
    for my $rc (@{$resp_cookies}) {
          my $cookie = Mojo::Cookie::Request->new;
          $cookie->name($rc->name);
          $cookie->value($rc->value);
          $cookie->path($rc->path);
          $cookie->version($rc->version) if defined $rc->version;

          push @req_cookies, $cookie;
    }

    return [@req_cookies];
}

sub crank_all {
    my $self = shift;

    my $active_count = 0;
    for my $id (keys %{$self->_active}) {
        $active_count += $self->crank_dest($id);
    }
    return $active_count;
}

sub crank_dest {
    my $self = shift;
    my $dest = shift;

    my $txs = $self->update_active($dest);

    return 0 unless (@{$txs}); # nothing currently active for this host:port

    $self->app ? $self->_spin_app($txs) : $self->_spin($txs);

    my @buffer;
    while (my $tx = shift @{$txs}) {

        if ($tx->is_finished) {

            $self->{_count}++;

            # Check for cookies
            $self->_extract_cookies($tx);

            # Check for redirect
            if ($tx->res->is_status_class(300)
                && $self->follow_redirects
                && $tx->hops < $self->redirect_limit
                && (my $location = $tx->res->headers->header('Location')))
            {

                # Presumably 304 (not modified) shouldn't include
                # a Location so shouldn't come in here...

                unless ($tx->res->code == 305) {

                    # Give priority to the new URL where it gives info,
                    # otherwise, keep elements of the old URL...
                    my $newu = Mojo::URL->new();
                    $newu->parse($location);
                    my $oldu = $tx->req->url;

                    $newu->scheme($oldu->scheme)       unless $newu->is_abs;
                    $newu->authority($oldu->authority) unless $newu->is_abs;

                    $newu->path($oldu->path)     unless $newu->path;
                    $newu->path($oldu->query)    unless $newu->query;
                    $newu->path($oldu->fragment) unless $newu->fragment;

                    # Note should check res->code to see if we should
                    # re-use the req->method...
                    my $new_tx = MojoX::UserAgent::Transaction->new(
                        {   url          => $newu,
                            method       => $tx->req->method,
                            hops         => $tx->hops + 1,
                            callback     => $tx->done_cb,
                            ua           => $self,
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

    # Put those not finished back into the active array for this host:port
    push @{$txs}, @buffer;

    return scalar @{$txs};
}

sub get {
    my $self = shift;
    my $url = shift;
    my $cb = shift || $self->default_done_cb;

    my $tx = MojoX::UserAgent::Transaction->new(
        {   url      => $url,
            callback => $cb,
            ua       => $self
        }
    );
    $self->spool_txs($tx);
}

sub run_all {
    my $self = shift;

    while (1) {
        last unless $self->crank_all;
    }
}

sub spool_txs {
    my $self = shift;
    my $new_transactions = [@_];
    for my $tx (@{$new_transactions}) {
        my ($scheme, $host, $port) = $tx->client_info;

        my $id = "$host:$port";
        if (my $ondeck = $self->_ondeck->{$id}) {
            push @{$ondeck}, $tx;
        }
        else {
            $self->_ondeck->{$id} = [$tx];
            $self->_active->{$id} = [];
        }
    }
}

sub update_active {
    my $self = shift;
    my $dest = shift;

    # Right now just copy from _ondeck to _active without any limitations

    my $ondeck = $self->_ondeck->{$dest};
    my $active = $self->_active->{$dest};

    if ($ondeck && @{$ondeck}) {
        push @{$active}, @{$ondeck};
        @{$ondeck} = ();
    }

    return $active;
}

sub _extract_cookies {
    my ($self, $tx) = @_;

    my $cookies = $tx->res->cookies;

    if (@{$cookies}) {
        my @cleared = $self->_scrub_cookies($tx, @{$cookies});
        $self->cookie_jar->store(@cleared) if @cleared;
    }


    1;
}

sub _scrub_cookies {
    my $self = shift;
    my $tx = shift;

    my @cookies = @_;
    my @cleared;

    for my $cookie (@cookies) {

        # Domain check
        if ($cookie->domain) {

            my $domain = $cookie->domain;
            my $host   = $tx->req->url->host;

            # strip any leading dot
            $cookie->domain($domain) if ($domain =~ s/^\.//);

            unless (   $domain =~ m{[\w\-]+\.[\w\-]+$}x
                    && ($host =~ s/\.$domain$//x || $host =~ s/^$domain$//x)
                    && $host !~ m{\.})
            {

                # Note that in theory we should add to this a refusal if
                # the domain matches one of these:
                # http://publicsuffix.org/list/
                next;
            }
        }
        else {
            $cookie->domain($tx->req->url->host);
        }

        # Port check
        if ($cookie->port) {

            # Should be comma separated list of numbers
            next unless $cookie->port =~ m/^[\d\,]+$/;
        }

        # Path check
        if ($cookie->path) {

            # Should be a prefix of the request URI
            if ($self->validate_cookie_paths) {
                my $cpath = $cookie->path;
                next unless ($tx->req->url->path =~ m/^$cpath/);
            }
        }
        else {
            $cookie->path($tx->req->url->path);
        }

        push @cleared, $cookie;
    }
    return @cleared;
}

sub _spin {
    my $self = shift;
    my $txs = shift;

    $self->_client->spin(@{$txs});
}
sub _spin_app {
    my $self = shift;
    my $txs = shift;

    #can only spin one so pick at random
    my $tx = $txs->[int(rand(scalar @{$txs}))];
    $self->_client->spin_app($self->{app}, $tx);
}


1;
__END__
