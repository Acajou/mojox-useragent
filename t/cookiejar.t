#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Mojo::URL;
use Mojo::Cookie::Response;
use MojoX::UserAgent::CookieJar;

plan tests => 12;

my $jar = MojoX::UserAgent::CookieJar->new;
my $cookie1 = Mojo::Cookie::Response->new;

$cookie1->name('foo');
$cookie1->value('1');
$cookie1->path('/foo');
$cookie1->domain('acajou.ca');
$cookie1->max_age(6000);

my $cookie2 = Mojo::Cookie::Response->new;

$cookie2->name('bar');
$cookie2->value('2');
$cookie2->path('/bar');
$cookie2->domain('acajou.ca');
$cookie2->max_age(6000);

my $cookie3 = Mojo::Cookie::Response->new;

$cookie3->name('host');
$cookie3->value('www');
$cookie3->path('/');
$cookie3->domain('www.acajou.ca');
$cookie3->max_age(6000);

$jar->store($cookie1, $cookie2, $cookie3);

is($jar->size, 3, "Stored 3 cookies");

my @returned;

@returned = $jar->cookies_for_url('http://boo.acajou.ca/foo/');

is(scalar @returned, 1, 'Jar returned right number of cookies.');
is($returned[0], $cookie1, 'Jar returned right cookie(s).');

@returned = $jar->cookies_for_url('http://bon.acajou.ca/bar/baz/');

is(scalar @returned, 1, 'Jar returned right number of cookies.');
is($returned[0], $cookie2, 'Jar returned right cookie(s).');

@returned = $jar->cookies_for_url('http://www.acajou.ca/');

is(scalar @returned, 1, 'Jar returned right number of cookies.');
is($returned[0], $cookie3, 'Jar returned right cookie(s).');

@returned = $jar->cookies_for_url('http://www.acajou.ca/foo/test#zop');

is(scalar @returned, 2, 'Jar returned right number of cookies.');


# Delete cookie
my $cookie_unset = Mojo::Cookie::Response->new;

$cookie_unset->name('host');
$cookie_unset->value('www');
$cookie_unset->path('/');
$cookie_unset->domain('www.acajou.ca');
$cookie_unset->max_age(0);

$jar->store($cookie_unset);

@returned = $jar->cookies_for_url('http://www.acajou.ca/foo/test#zop');

is($jar->size, 2, "One cookie removed");
is(scalar @returned, 1, 'Jar returned right number of cookies.');
is($returned[0], $cookie1, 'Jar returned right cookie(s).');

@returned = $jar->cookies_for_url('http://www.not.ca/foo/test#zop');
is(scalar @returned, 0, 'Jar returned right number of cookies.');
