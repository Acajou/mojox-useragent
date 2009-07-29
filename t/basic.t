#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use MojoX::UserAgent;

plan tests => 1;

my $ua = MojoX::UserAgent->new;

isa_ok($ua, "MojoX::UserAgent");

my $tx1 =  Mojo::Transaction->new_get('http://127.0.0.1:3000/');

$ua->spool_tx($tx1);

$ua->run_all;

my $tx2  = Mojo::Transaction->new_get('http://labs.kraih.com');

$ua->spool_tx($tx2);

$ua->run_all;
