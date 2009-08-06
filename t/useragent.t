#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use MojoX::UserAgent;

plan tests => 32;

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
        elsif ($tx->req->url->path =~ m{^/multi}) {

            my $cookie1 = Mojo::Cookie::Response->new;
            $cookie1->name('multi1');
            $cookie1->value('111');
            $cookie1->path('/');
            $cookie1->domain('notreal.com');
            $cookie1->max_age(6000);

            my $cookie2 = Mojo::Cookie::Response->new;
            $cookie2->name('multi2');
            $cookie2->value('222');
            $cookie2->path('/');
            $cookie2->domain('notreal.com');
            $cookie2->max_age(6000);

            $tx->res->code(302);
            $tx->res->headers->set_cookie($cookie1, $cookie2);
            $tx->res->headers->location('/echo');
        }
        elsif ($tx->req->url->path =~ m{^/baddomain}) {

            my $cookie1 = Mojo::Cookie::Response->new;
            $cookie1->name('testevil');
            $cookie1->value('shouldntwork');
            $cookie1->path('/');
            $cookie1->domain('eal.com');
            $cookie1->max_age(6000);

            my $cookie2 = Mojo::Cookie::Response->new;
            $cookie2->name('testevil2');
            $cookie2->value('shouldntwork');
            $cookie2->path('/');
            $cookie2->domain('.com');
            $cookie2->max_age(6000);

            $tx->res->code(302);
            $tx->res->headers->set_cookie($cookie1, $cookie2);
            $tx->res->headers->location('/echo');
        }
        elsif ($tx->req->url->path =~ m{^/twolevelsup}) {

            my $domain = $tx->req->url->to_abs->host;
            $domain =~ s/^(\w+\.\w+\.)//;
            my $cookie = Mojo::Cookie::Response->new;
            $cookie->name('testevil');
            $cookie->value('shouldntwork');
            $cookie->path('/');
            $cookie->domain("$domain");
            $cookie->max_age(6000);

            $tx->res->code(302);
            $tx->res->headers->set_cookie($cookie);
            $tx->res->headers->location('/echo');
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

        is($tx->res->code,      200,     "Test1 (set cookie) - Status 200");
        is($tx->hops,           1,       "Test1 - 1 hop");
        is($tx->req->url->path, '/echo', "Test1 - request path OK");
        is($tx->req->url, 'http://www.notreal.com/echo',
            "Test1 - request url OK");
        is($tx->res->headers->content_type,
            'text/plain', "Test1 - content-type OK");
        like($tx->res->body, qr/testcookie=1969/, "Test1 - cookie OK");
    }
);

$ua->run_all;

$ua->app($app);

$ua->get(
    'http://www.notreal.com/unset/',
    sub {
        my ($ua_r, $tx) = @_;

        is($tx->res->code,      200,     "Test2 (unset cookie) - Status 200");
        is($tx->hops,           1,       "Test2 - 1 hop");
        is($tx->req->url->path, '/echo', "Test2 - request path OK");
        is($tx->req->url, 'http://www.notreal.com/echo',
            "Test2 - request url OK");
        is($tx->res->headers->content_type,
            'text/plain', "Test2 - content-type OK");
        unlike($tx->res->body, qr/testcookie=1969/, "Test2 - cookie gone");
    }
);

$ua->run_all;

$ua->get(
    'http://www.notreal.com/loop/0',
    sub {
        my ($ua_r, $tx) = @_;

        is($tx->res->code, 302, "Test3 (request loop) - Status 302");
        is($tx->hops, 10, "Test3 - 10 hops");
        is($tx->req->url->path, '/loop/10', "Test3 - request path OK");
        is( $tx->req->url,
            'http://www.notreal.com/loop/10',
            "Test3 - request url OK"
        );
    }
);

$ua->run_all;

$ua->get(
    'http://www.notreal.com/multi/',
    sub {
        my ($ua_r, $tx) = @_;

        is($tx->res->code, 200, "Test4 (multiple set-cookie) - Status 200");
        is($tx->hops, 1, "Test4 - 1 hop");
        is($tx->req->url->path, '/echo', "Test4 - request path OK");
        like($tx->res->body, qr/multi1=111/, "Test4 - 1st cookie found");
        like($tx->res->body, qr/multi2=222/, "Test4 - 2nd cookie found");
    }
);

$ua->run_all;


$ua->get(
    'http://www.notreal.com/baddomain/',
    sub {
        my ($ua_r, $tx) = @_;

        is($tx->res->code, 200, "Test5 (bad cookie domains) - Status 200");
        is($tx->hops, 1, "Test5 - 1 hop");
        is($tx->req->url->path, '/echo', "Test5 - request path OK");
        unlike($tx->res->body, qr/testevil/, "Test5 - bad cookie absent");
    }
);

$ua->run_all;


$ua->get(
    'http://www.eal.com/echo/',
    sub {
        my ($ua_r, $tx) = @_;

        is($tx->res->code, 200, "Test5 - Status 200");
        unlike($tx->res->body, qr/testevil/, "Test5 - bad cookie absent");
    }
);

$ua->run_all;

$ua->get(
    'http://www.foo.notreal.com/twolevelsup/',
    sub {
        my ($ua_r, $tx) = @_;

        is($tx->res->code, 200,
            "Test6 (cookie domain two levels up) - Status 200");
        is($tx->hops, 1, "Test6 - 1 hop");
        is( $tx->req->url,
            'http://www.foo.notreal.com/echo',
            "Test6 - request url OK"
        );
        unlike($tx->res->body, qr/testevil/, "Test6 - bad cookie absent");
    }
);

$ua->run_all;
