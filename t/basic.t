#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use MojoX::UserAgent;

plan tests => 13;

my $ua = MojoX::UserAgent->new;

isa_ok($ua, "MojoX::UserAgent");
isa_ok($ua, "Mojo::Base");

$ua->spool_get(
    'http://labs.kraih.com',
    sub {
        my ($ua_r, $tx) = @_;

        isa_ok($ua_r, "MojoX::UserAgent");
        isa_ok($tx, "MojoX::UserAgent::Transaction");
        is($ua, $ua_r, "User-Agent object match");

        is($tx->res->code, 200, "labs.kraih.com - Status 200");
        is($tx->hops, 1, "labs.kraih.com - 1 hop");
    }
);

$ua->run_all;

$ua->spool_get(
    'http://www.djembe.ca',
    sub {
        my ($ua_r, $tx) = @_;
        is($tx->res->code, 200, "www.djembe.ca - Status 200");
        is($tx->hops, 2, "www.djembe.ca - 2 hops");
    }
);

$ua->spool_get(
    'http://search.cpan.org/dist/Mojo/',
    sub {
        my ($ua_r, $tx) = @_;
        is($tx->res->code, 200, "search.cpan.org - Status 200");
        is($tx->hops, 0, "search.cpan.org - no hops");
    }
);

$ua->spool_get(
    'http://mojolicious.org',
    sub {
        my ($ua_r, $tx) = @_;
        is($tx->res->code, 200, "mojolicious.org - Status 200");
        is($tx->hops, 0, "mojolicious.org - no hops");
    }
);

$ua->run_all;
