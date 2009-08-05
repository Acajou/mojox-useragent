#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use MojoX::UserAgent;

plan tests => 17;

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
        elsif ($tx->req->url->path =~ m{^/loop/(\d+)}) {

            my $x = $1;
            $x++;
            $tx->res->code(302);
            $tx->res->headers->location("/loop/$x");
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

        is($tx->res->code, 200, "Test1 (set) - Status 200");
        is($tx->hops, 1, "Test1 (set) - 1 hop");
        is($tx->req->url->path, '/echo',
            "Test1 (set) - request path OK");
        is($tx->req->url, 'http://www.notreal.com/echo',
            "Test1 (set) - request url OK");
        is($tx->res->headers->content_type, 'text/plain',
            "Test1 (set) - content-type OK");
        like($tx->res->body, qr/testcookie=1969/,
            "Test1 (set) - cookie OK");
    }
);

$ua->run_all;

$ua->app($app);

$ua->get(
    'http://www.notreal.com/unset/',
    sub {
        my ($ua_r, $tx) = @_;

        is($tx->res->code, 200, "Test2 (unset) - Status 200");
        is($tx->hops, 1, "Test2 (unset) - 1 hop");
        is($tx->req->url->path, '/echo',
            "Test2 (unset) - request path OK");
        is($tx->req->url, 'http://www.notreal.com/echo',
            "Test2 (unset) - request url OK");
        is($tx->res->headers->content_type, 'text/plain',
            "Test2 (unset) - content-type OK");
        unlike($tx->res->body, qr/testcookie=1969/,
            "Test2 (unset) - cookie gone");
    }
);

$ua->run_all;

$ua->get(
    'http://www.notreal.com/loop/0',
    sub {
        my ($ua_r, $tx) = @_;

        is($tx->res->code, 302, "Test3 (loop) - Status 302");
        is($tx->hops, 10, "Test3 (loop) - 10 hops");
        is($tx->req->url->path, '/loop/10',
            "Test3 (loop) - request path OK");
        is($tx->req->url, 'http://www.notreal.com/loop/10',
            "Test3 (loop) - request url OK");
    }
);

$ua->run_all;
