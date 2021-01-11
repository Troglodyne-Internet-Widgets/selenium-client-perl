package Selenium::Driver::Edge;

use strict;
use warnings;

no warnings 'experimental';
use feature qw/signatures/;

use parent qw{Selenium::Driver::Chrome};

#ABSTRACT: Tell Selenium::Client how to spawn edgedriver

=head1 Mode of Operation

Like edge, this is a actually chrome.  So refer to Selenium::Driver::Chrome documentation.

=cut

sub _driver {
    return 'msedgedriver.exe';
}

1;
