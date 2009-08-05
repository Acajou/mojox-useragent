package MojoX::UserAgent::Transaction;

use warnings;
use strict;
use diagnostics;

use base 'Mojo::Transaction';

use Carp 'croak';

__PACKAGE__->attr('hops', default => 0);
__PACKAGE__->attr('done_cb');
__PACKAGE__->attr('id');
__PACKAGE__->attr('original_req');
__PACKAGE__->attr('ua');

sub new {
    my $self = shift->SUPER::new();

    my ($arg_ref) = @_;
    my $req = $self->req;

    croak('Missing arguments')
      if (   !defined($arg_ref->{url})
          || !defined($arg_ref->{callback})
          || !defined($arg_ref->{ua}));

    my $url = $arg_ref->{url};
    ref $url && $url->isa('Mojo::URL')
      ? $req->url($url)
      : $req->url->parse($url);

    $self->done_cb($arg_ref->{callback});
    $self->ua($arg_ref->{ua});

    if ($arg_ref->{headers}) {
        my $headers = $arg_ref->{headers};
        for my $name (keys %{$headers}) {
            $req->headers->header($name, $headers->{$name});
        }
    }

    $req->method($arg_ref->{method}) if $arg_ref->{method};
    $self->id($arg_ref->{id}) if $arg_ref->{id};

    # Not sure if I should allow hops or
    # original_req in the constructor...
    $self->hops($arg_ref->{hops}) if $arg_ref->{hops};
    $self->original_req($arg_ref->{original_req}) if $arg_ref->{original_req};

    return $self;
}

sub client_connect {
    my $self = shift->SUPER::client_connect();

    # Add cookies
    my $cookies = $self->ua->cookies_for_url($self->req->url);

    # What if req already had some cookies?
    $self->req->cookies(@{$cookies});

    return $self;
}
1;
