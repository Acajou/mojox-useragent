package MojoX::UserAgent;

use warnings;
use strict;

use base 'Mojo::Base';

use Carp 'croak';

use Mojo 0.991247;

use Mojo::URL;
use Mojo::Pipeline;
use Mojo::Client;
use Mojo::Cookie;
use MojoX::UserAgent::Transaction;
use MojoX::UserAgent::CookieJar;

our $VERSION = '0.1';

__PACKAGE__->attr('follow_redirects' => 1);
__PACKAGE__->attr('redirect_limit' => 10);

# pipeline_method: 'none' / 'horizontal' / 'vertical'
__PACKAGE__->attr('pipeline_method' => 'none');

__PACKAGE__->attr('validate_cookie_paths' => 0);

__PACKAGE__->attr('cookie_jar' => sub { MojoX::UserAgent::CookieJar->new });

__PACKAGE__->attr(
    'agent' => "Mozilla/5.0 (compatible; MojoX::UserAgent/$VERSION)");

__PACKAGE__->attr(
    'default_done_cb' => sub {
        return sub {
            my ($self, $tx) = @_;
            my $url = $tx->hops ? $tx->original_req->url : $tx->req->url;
            print "$url done in " . $tx->hops . " hops.\n";
        };
    }
);

__PACKAGE__->attr('_count' => 0);

__PACKAGE__->attr('_client' => sub { Mojo::Client->new });

__PACKAGE__->attr('_maxconnections' => 5);
__PACKAGE__->attr('_maxpipereqs' => 5);

__PACKAGE__->attr('_active' => sub { {} });
__PACKAGE__->attr('_ondeck' => sub { {} });


__PACKAGE__->attr('app');

# Subroutine declarations
sub _pipe_no;
sub _pipe_h;
sub _pipe_v;

__PACKAGE__->attr(
    '_pipe_methods' => sub {
        {   'none'       => \&_pipe_no,
            'horizontal' => \&_pipe_h,
            'vertical'   => \&_pipe_v,
        };
    }
);

# Subroutine declarations
sub _find_finished_nopipe;
sub _find_finished_pipe;

__PACKAGE__->attr(
    '_find_finished' => sub {
        {   'none'       => \&_find_finished_nopipe,
            'horizontal' => \&_find_finished_pipe,
            'vertical'   => \&_find_finished_pipe
        };
    }
);

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

    # Update the active queue
    my $active = $self->_update_active($dest);

    return 0 unless (@{$active}); # nothing currently active for this host:port

    $self->app ? $self->_spin_app($active) : $self->_spin($active);

    my @still_active;
    my @finished;

    # Use appropriate sub to find finished txs based on pipelining method
    my $zesub = $self->_find_finished->{$self->pipeline_method};
    $self->$zesub($active, \@still_active, \@finished);

    for my $tx (@finished) {

        # TODO: need to check for tx errors here!
        $self->{_count}++;

        # Check for cookies
        $self->_extract_cookies($tx);

        # Check for redirect
        if (   $tx->res->is_status_class(300)
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

                # TODO: check res->code to see if we should
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

    # Put those not finished back into the active array for this host:port
    push @{$active}, @still_active;

    return scalar @{$active};
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

sub is_idle {
    my $self = shift;

    return (!(scalar keys %{$self->_active})
             && !(scalar keys %{$self->_ondeck}));
}

sub maxconnections {
    my $self = shift;
    my $value = shift;

    return $self->_maxconnections unless $value;

    $self->is_idle
      ? return $self->_maxconnections($value)
      : return $self->_maxconnections;
}

sub maxpipereqs {
    my $self = shift;
    my $value = shift;

    return $self->_maxpipereqs unless $value;

    $self->is_idle
      ? return $self->_maxpipereqs($value)
      : return $self->_maxpipereqs;
}

sub run_all {
    my $self = shift;

    while (1) {
        $self->crank_all;
        last if $self->is_idle;
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

sub _extract_cookies {
    my ($self, $tx) = @_;

    my $cookies = $tx->res->cookies;

    if (@{$cookies}) {
        my $cleared = $self->_scrub_cookies($tx, $cookies);
        $self->cookie_jar->store($cleared) if @{$cleared};
    }


    1;
}

sub _find_finished_pipe {
    my ($self, $active, $still_active, $finished) = @_;

    while (my $tx = shift @{$active}) {
        if ($tx->is_finished) {

            # if it's a pipeline, we must unpack
            if (ref $tx eq 'Mojo::Pipeline') {
                for my $inner (@{$tx->transactions}) {
                    push @{$finished}, $inner;
                }
            }
            else {
                push @{$finished}, $tx;
            }
        }
        else {
            # TODO: get finished transactions from pipeline here
            # (needs Mojo change first)
            push @{$still_active}, $tx;
        }
    }

}

sub _find_finished_nopipe {
    my ($self, $active, $still_active, $finished) = @_;

    while (my $tx = shift @{$active}) {
        $tx->is_finished
          ? push @{$finished}, $tx
          : push @{$still_active}, $tx;
    }

}

sub _pipe_h_or_v() {
    my ($self, $h_or_v, $slots, $ondeck, $active) = @_;

    my $queue_max = $slots * $self->maxpipereqs;

    my @stage;
    my $i=0;
    my $j=0;
    my $queued=0;

    while ($queued < $queue_max && @{$ondeck}) {

        $stage[$i] = [] unless $stage[$i];

        $stage[$i]->[$j] = shift @{$ondeck};
        $queued++;

        if ($h_or_v) {

            # Vertical
            $j++;
            if ($j == $self->maxpipereqs) {
                $j = 0;
                $i++;
            }
        }
        else {

            # Horizontal
            $i++;
            if ($i == $slots) {
                $i = 0;
                $j++;
            }
        }
    }

    foreach my $slot (@stage) {
        if (scalar @{$slot} == 1) {
            push @{$active}, $slot->[0];
        }
        else {
            my $pipe = Mojo::Pipeline->new(@{$slot});
            push @{$active}, $pipe;
        }
    }
}

sub _pipe_h {
    my $self= shift;

    $self->_pipe_h_or_v(0, @_);

}

sub _pipe_no {
    my ($self, $slots, $ondeck, $active) = @_;

    my $i=0;
    while ($i<$slots && @{$ondeck}) {
        push @{$active}, (shift @{$ondeck});
        $i++;
    }
}

sub _pipe_v() {
    my $self= shift;

    $self->_pipe_h_or_v(1, @_);

}

sub _scrub_cookies {
    my $self = shift;
    my $tx = shift;
    my $cookies = shift;

    my @cleared = ();

    for my $cookie (@{$cookies}) {

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

        # Clean max-age
        if ($cookie->max_age) {

            # Integer number - only digits
            next unless $cookie->max_age =~ m/^\d+$/;
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
    return \@cleared;
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

sub _update_active {
    my $self = shift;
    my $dest = shift;

    my $ondeck = $self->_ondeck->{$dest};
    my $active = $self->_active->{$dest};

    my $on_count = scalar @{$ondeck};
    my $act_count = scalar @{$active};

    if (!$act_count && !$on_count) {
        # nothing active or ondeck for this host/port: delete hash entries
        delete $self->_ondeck->{$dest};
        delete $self->_active->{$dest};
        return [];
    }

    if (@{$ondeck} && $act_count < $self->maxconnections) {

        # Use appropriate method to add to the active queue
        my $slots = $self->maxconnections - $act_count;
        my $zesub = $self->_pipe_methods->{$self->pipeline_method};
        $self->$zesub($slots, $ondeck, $active);
    }

    return $active;
}


1;
__END__
