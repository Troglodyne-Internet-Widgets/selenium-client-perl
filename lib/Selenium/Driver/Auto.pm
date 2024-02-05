package Selenium::Driver::Auto;

#ABSTRACT: Automatically choose the best driver available for your browser choice

use strict;
use warnings;

use Carp qw{confess};
use File::Which;

# Abstract: Automatically figure out which driver you want

=head1 SUBROUTINES

=head2 build_spawn_opts($class,$object)

Builds a command string which can run the driver binary.
All driver classes must build this.

=cut

sub build_spawn_opts {

    # Uses object call syntax
    my ( undef, $object ) = @_;

    if ( $object->{browser} eq 'firefox' ) {
        require Selenium::Driver::Gecko;
        return Selenium::Driver::Gecko->build_spawn_opts($object);
    }
    elsif ( $object->{browser} eq 'chrome' ) {
        require Selenium::Driver::Chrome;
        return Selenium::Driver::Chrome->build_spawn_opts($object);
    }
    elsif ( $object->{browser} eq 'MicrosoftEdge' ) {
        require Selenium::Driver::Edge;
        return Selenium::Driver::Edge->build_spawn_opts($object);
    }
    elsif ( $object->{browser} eq 'safari' ) {
        require Selenium::Driver::Safari;
        return Selenium::Driver::Safari->build_spawn_opts($object);
    }
    require Selenium::Driver::SeleniumHQ::Jar;
    return Selenium::Driver::SeleniumHQ::Jar->build_spawn_opts($object);
}

1;
