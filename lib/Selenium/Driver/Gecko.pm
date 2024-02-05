package Selenium::Driver::Gecko;

use strict;
use warnings;

use v5.28;

no warnings 'experimental';
use feature qw/signatures/;

use Carp qw{confess};
use File::Which;

#ABSTRACT: Tell Selenium::Client how to spawn geckodriver

=head1 Mode of Operation

Spawns a geckodriver server on the provided port (which the caller will assign randomly)
Relies on geckodriver being in your $PATH
Pipes log output to ~/.selenium/perl-client/$port.log

=head1 SUBROUTINES

=head2 build_spawn_opts($class,$object)

Builds a command string which can run the driver binary.
All driver classes must build this.

=cut

sub build_spawn_opts ( $class, $object ) {
    $object->{driver_class} = $class;
    $object->{driver_version} //= '';
    $object->{log_file}       //= "$object->{client_dir}/perl-client/selenium-$object->{port}.log";
    $object->{driver_file} = File::Which::which('geckodriver');
    die "Could not find driver!" unless $object->{driver_file};

    my @config = ( '--port', $object->{port} );

    # Build command string
    $object->{command} //= [
        $object->{driver_file},
        @config,
    ];
    return $object;
}

1;
