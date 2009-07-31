#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use MojoX::UserAgent;

plan tests => 2;

my $ua = MojoX::UserAgent->new;

isa_ok($ua, "MojoX::UserAgent");
isa_ok($ua, "Mojo::Base");

my $tx1 =  Mojo::Transaction->new_get('http://127.0.0.1:3000/');

$ua->spool_txs($tx1);

$ua->run_all;

my $tx2 = Mojo::Transaction->new_get('http://labs.kraih.com');

$ua->spool_txs($tx2);

$ua->run_all;

my $tx3 = Mojo::Transaction->new_get('http://www.djembe.ca');
my $tx4 = Mojo::Transaction->new_get('http://mojolicious.org');
my $tx5 = Mojo::Transaction->new_get('http://search.cpan.org/dist/Mojo/');

$ua->spool_txs($tx3, $tx4, $tx5);

$ua->run_all;
