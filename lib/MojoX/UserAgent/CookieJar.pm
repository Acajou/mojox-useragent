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

        # Note to self: check DNS spec(s) for use of extended characters
        # in domain names... (ie \w might not cut it...)
        $cookie->domain =~ m/(\w+\.\w+)$/x;
        my $sld = $1;    # Second Level Domain (eg google.ca)

        if ($self->_jar->{$sld}) {

            # Do we already have this cookie?
            my $found = 0;
            for my $i (0 .. $#{$self->_jar->{$sld}}) {

                my $candidate = $self->_jar->{$sld}->[$i];
                if (   $candidate->domain eq $cookie->domain
                    && $candidate->path eq $cookie->path
                    && $candidate->name eq $cookie->name)
                {

                    # Check for unset
                    if (   $cookie->max_age
                        && $cookie->max_age == 0)
                    {
                        splice @{$self->_jar->{$sld}}, $i, 1;
                        $self->{size}--;
                    }
                    else {

                        # Got a match: replace.
                        # Should this be in-place (as below), or should we
                        # delete the old one and push new one?
                        $self->_jar->{$sld}->[$i] = $cookie;
                        $found = 1;
                    }
                }
            }
            unless ($found) {
                push @{$self->_jar->{$sld}}, $cookie;
                $self->{size}++;
            }
        }
        else {
            $self->_jar->{$sld} = [$cookie];
            $self->{size}++;
        }
    }
    return $self->size;
}

sub cookies_for_url {
    my $self = shift;
    my $url = shift;

    return;
}


1;
