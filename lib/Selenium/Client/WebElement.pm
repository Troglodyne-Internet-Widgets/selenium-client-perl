package Selenium::Client::WebElement;

# ABSTRACT: Representation of an HTML Element used by Selenium Client Driver

use strict;
use warnings;

use parent qw{Selenium::Remote::WebElement};

no warnings qw{experimental};
use feature qw{signatures};

use Carp::Always;

=head1 DESCRIPTION

Subclass of Selenium::Remote::WebElement.

Implements the bare minimum to shim in Selenium::Client as a backend for talking to selenium 4 servers.

See the documentation for L<Selenium::Remote::WebElement> for details about methods, unless otherwise noted below.

=cut

sub _param ($self, $default, $param, $value=undef) {
    $self->{$param} //= $default;
    $self->{$param} = $value if defined $value;
    return $self->{$param};
}

sub element($self, $element=undef) {
    return $self->_param(undef, 'element', $element);
}

sub driver($self, $driver=undef) {
    return $self->_param(undef, 'driver', $driver);
}

sub session($self, $session=undef) {
    return $self->_param(undef, 'session', $session);
}

sub new($class,%options) {
    my $self = bless(\%options, $class);
    $self->id($self->element->{'element-6066-11e4-a52e-4f735466cecf'});
    return $self;
}

sub id ($self,$value=undef) {
    return $self->_param(undef, 'id', $value);
}

1;
