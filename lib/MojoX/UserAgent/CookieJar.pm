package MojoX::UserAgent::CookieJar;

use warnings;
use strict;
use diagnostics;

use base 'Mojo::Base';

use Carp 'croak';

__PACKAGE__->attr('_jar', default => sub { {} });
__PACKAGE__->attr('size', default => 0);

sub store {
    my $self = shift;
    my $cookies = [@_];

    for my $cookie (@{$cookies}) {

        croak('Can\'t store cookie without domain') unless $cookie->domain;

        my $domain = $cookie->domain;
        my $store = $self->_jar->{$domain};

        if ($store) {

            # Do we already have this cookie?
            my $found = 0;
            for my $i (0 .. $#{$store}) {

                my $candidate = $store->[$i];
                if (   $candidate->domain eq $cookie->domain
                    && $candidate->path eq $cookie->path
                    && $candidate->name eq $cookie->name)
                {

                    $found = 1;

                    # Check for unset
                    if (defined $cookie->max_age
                        && $cookie->max_age == 0)
                    {
                        splice @{$store}, $i, 1;
                        $self->{size}--;
                    }
                    else {

                        # Got a match: replace.
                        # Should this be in-place (as below), or should we
                        # delete the old one and push new one?
                        $store->[$i] = $cookie;
                    }

                    last;
                }
            }

            unless ($found) {
                # push may not be enough here, might want to order by
                # longest path?
                push @{$store}, $cookie;
                $self->{size}++;
            }
        }
        else {
            $self->_jar->{$domain} = [$cookie];
            $self->{size}++;
        }
    }
    return $self->size;
}

sub cookies_for_url {
    my $self = shift;
    my $url = shift;

    croak 'Must provide url' unless $url;

    my @cookies = ();
    my $urlobj = Mojo::URL->new;

    ref $url && $url->isa('Mojo::URL')
      ? $urlobj = $url
      : $urlobj->parse($url);

    croak 'Url must be absolute' unless $urlobj->is_abs;

    my $domain = $urlobj->host;

    do {
        my $store = $self->_jar->{$domain};

        if ($store) {

            for my $i (0 .. $#{$store}) {

                my $candidate = $store->[$i];
                my $path      = $candidate->path;

                if ($urlobj->path =~ m{^$path}) {
                    unless ($candidate->port) {
                        push @cookies, $candidate;
                    }
                    else {
                        my $port = $urlobj->port || '80';
                        push @cookies, $candidate
                          if ($candidate->port =~ m{\b$port\b});
                    }
                }
            }
        }
    } while ($domain =~ s{^\w+\.(.*)}{$1}x && $domain =~ m{(\w+\.\w+)$}x);
    # Note to self: check DNS spec(s) for use of extended characters
    # in domain names... (ie \w might not cut it...)

    return [@cookies];
}


1;
