#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use MojoX::UserAgent;

plan tests => 13;

my $ua = MojoX::UserAgent->new;

{
    package CookieTest;

    use strict;
    use warnings;

    use base 'Mojo::HelloWorld';

    sub handler {
        my ($self, $tx) = @_;

        if ($tx->req->url->path =~ m{^/set}) {

            my $cookie = Mojo::Cookie::Response->new;
            $cookie->name('testcookie');
            $cookie->value('1969');
            $cookie->path('/');

            my $url = $tx->req->url->to_abs;
            $url->path('/echo');
            $tx->res->code(302);
            $tx->res->headers->set_cookie($cookie);
            $tx->res->headers->location($url);
        }
        elsif ($tx->req->url->path =~ m{^/echo}) {

            my $cookies = $tx->req->cookies;

            my $body = "xyz";
            for my $cookie (@{$cookies}) {
                $body .= $cookie->to_string . "\n";

            }
            $tx->res->code(200);
            $tx->res->headers->content_type('text/plain');

            $tx->res->body($body);

        }
        elsif ($tx->req->url->path =~ m{^/unset}) {

            my $cookie = Mojo::Cookie::Response->new;
            $cookie->name('testcookie');
            $cookie->value('nomatter');
            $cookie->path('/');
            $cookie->max_age(0);

            $tx->res->code(302);
            $tx->res->headers->location('/echo');
            $tx->res->headers->set_cookie($cookie);
        }
        else {
            my $url = $tx->req->url->to_abs;
            $url->path('/echo');
            $tx->res->code(302);
            $tx->res->headers->location($url);
        }
    }
}

my $app = CookieTest->new;
isa_ok($app, "Mojo::HelloWorld");

$ua->app($app);

$ua->get(
    'http://www.notreal.com/set/',
    sub {
        my ($ua_r, $tx) = @_;

        is($tx->res->code, 200, "Cookie Test1 - Status 200");
        is($tx->hops, 1, "Cookie Test1 - 1 hop");
        is($tx->req->url->path, '/echo',
            "Cookie Test1 - request path OK");
        is($tx->req->url, 'http://www.notreal.com/echo',
            "Cookie Test1 - request url OK");
        is($tx->res->headers->content_type, 'text/plain',
            "Cookie Test1 - content-type OK");
        like($tx->res->body, qr/testcookie=1969/,
            "Cookie Test1 - cookie OK");
    }
);

$ua->run_all;

$ua->app($app);

$ua->get(
    'http://www.notreal.com/unset/',
    sub {
        my ($ua_r, $tx) = @_;

        is($tx->res->code, 200, "Cookie Test2 - Status 200");
        is($tx->hops, 1, "Cookie Test2 - 1 hop");
        is($tx->req->url->path, '/echo',
            "Cookie Test2 - request path OK");
        is($tx->req->url, 'http://www.notreal.com/echo',
            "Cookie Test2 - request url OK");
        is($tx->res->headers->content_type, 'text/plain',
            "Cookie Test2 - content-type OK");
        unlike($tx->res->body, qr/testcookie=1969/,
            "Cookie Test2 - cookie gone");
    }
);

$ua->run_all;
