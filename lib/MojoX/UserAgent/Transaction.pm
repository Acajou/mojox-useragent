package MojoX::UserAgent::Transaction;

use warnings;
use strict;
use diagnostics;

use base 'Mojo::Transaction::Single';

use Carp 'croak';

__PACKAGE__->attr('hops' => 0);
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
          || !defined($arg_ref->{ua}));

    my $url = $arg_ref->{url};
    ref $url && $url->isa('Mojo::URL')
      ? $req->url($url)
      : $req->url->parse($url);

    $self->ua($arg_ref->{ua});

    $arg_ref->{callback}
      ? $self->done_cb($arg_ref->{callback})
      : $self->done_cb($self->ua->default_done_cb);

    if ($arg_ref->{headers}) {
        my $headers = $arg_ref->{headers};
        for my $name (keys %{$headers}) {
            $req->headers->$name($headers->{$name});
        }
    }

    $req->method($arg_ref->{method}) if $arg_ref->{method};
    $req->body($arg_ref->{body}) if $arg_ref->{body};

    $self->id($arg_ref->{id}) if $arg_ref->{id};

    # Not sure if I should allow hops or
    # original_req in the constructor...
    $self->hops($arg_ref->{hops}) if $arg_ref->{hops};
    $self->original_req($arg_ref->{original_req}) if $arg_ref->{original_req};

    return $self;
}

sub client_connect {
    my $self = shift;

    # Add cookies
    my $cookies = $self->ua->cookies_for_url($self->req->url);
    # What if req already had some cookies?
    $self->req->cookies(@{$cookies});

    unless ($self->req->headers->user_agent) {
        my $ua = $self->ua->agent;
        $self->req->headers->user_agent($ua) if $ua;
    }

    $self->SUPER::client_connect();
    return $self;
}
1;
