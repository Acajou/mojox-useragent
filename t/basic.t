#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use MojoX::UserAgent;

plan tests => 2;

my $ua = MojoX::UserAgent->new;

isa_ok($ua, "MojoX::UserAgent");
isa_ok($ua, "Mojo::Base");

$ua->spool_get('http://127.0.0.1:3000/');

$ua->run_all;

$ua->spool_get('http://labs.kraih.com');

$ua->run_all;

$ua->spool_get('http://www.djembe.ca');
$ua->spool_get('http://mojolicious.org');
$ua->spool_get('http://search.cpan.org/dist/Mojo/');

$ua->run_all;
