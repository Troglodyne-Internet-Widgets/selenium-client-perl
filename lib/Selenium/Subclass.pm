package Selenium::Subclass;

#ABSTRACT: Generic template for Selenium sugar subclasses like Selenium::Session

use strict;
use warnings;

use v5.28;

no warnings 'experimental';
use feature qw/signatures/;

=head1 CONSTRUCTOR

=head2 $class->new($parent Selenium::Client, $data HASHREF)

You should probably not use this directly; objects should be created as part of normal operation.

=cut

sub new ( $class, $parent, $data ) {
    my %lowkey;
    @lowkey{ map { lc $_ } keys(%$data) } = values(%$data);
    $lowkey{parent} = $parent;

    my $self = bless( \%lowkey, $class );

    $self->_build_subs($class);

    # Make sure this is set so we can expose it for use it in various other calls by end-users
    if ( $self->{sortfield} eq 'element-6066-11e4-a52e-4f735466cecf' ) {
        $self->{sortfield} = 'elementid';
        $self->{elementid} = delete $self->{'element-6066-11e4-a52e-4f735466cecf'};
    }

    return $self;
}

sub _request ( $self, $method, %params ) {

    #XXX BAD SPEC AUTHOR, BAD!
    if ( $self->{sortfield} eq 'elementid' ) {

        # Ensure element childs don't think they are their parent
        $self->{to_inject}{elementid} = $self->{elementid};
    }

    # Inject our sortField param, and anything else we need to
    $params{ $self->{sortfield} } = $self->{ $self->{sortfield} };
    my $inject = $self->{to_inject};
    @params{ keys(%$inject) } = values(%$inject) if ref $inject eq 'HASH';

    # and ensure it is injected into child object requests
    # This is primarily to ensure that the session ID trickles down correctly.
    # Some also need the element ID to trickle down.
    # However, in the case of getting child elements, we wish to specifically prevent that, and do so above.
    $params{inject} = $self->{sortfield};

    $self->{callback}->( $self, $method, %params ) if $self->{callback};

    return $self->{parent}->_request( $method, %params );
}

sub DESTROY ($self) {
    return                             if ${^GLOBAL_PHASE} eq 'DESTRUCT';
    $self->{destroy_callback}->($self) if $self->{destroy_callback};
}

#TODO filter spec so we don't need parent anymore, and can have a catalog() method
sub _build_subs ( $self, $class ) {

    #Filter everything out which doesn't have {sortField} in URI
    my $k = lc( $self->{sortfield} );

    #XXX deranged field name
    $k = 'elementid' if $self->{sortfield} eq 'element-6066-11e4-a52e-4f735466cecf';

    foreach my $sub ( keys( %{ $self->{parent}{spec} } ) ) {
        next unless $self->{parent}{spec}{$sub}{uri} =~ m/{\Q$k\E}/;
        Sub::Install::install_sub(
            {
                code => sub {
                    my $self = shift;
                    return $self->_request( $sub, @_ );
                },
                as   => $sub,
                into => $class,
            }
        ) unless $class->can($sub);
    }
}

1;
