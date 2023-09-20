package Selenium::Client::Commands;

use strict;
use warnings;

# Polyfill from Selenium 4's spec to JSONWire + Selenium 3

my %command_map = (
    'status' => {
        driver => 1,
        execute => sub {
            my ($driver,$params) = @_;
            return $driver->Status();
        },
        parse  => sub {
            my ($driver, $ret) = @_;
            return $ret->{ready};
        },
    },
    'newSession' => {
        driver => 1,
        execute => sub {
            my ($driver, $params) = @_;
            return [$driver->NewSession($params)];
        },
        parse => sub {
            my ($driver, $ret) = @_;
            my ($capabilities, $session) = @$ret;
            return { capabilities => $capabilities, session => $session };
        },
    },
    #XXX maybe valuable to ask the server? idk, seems harmful to fiddle with others' sessions
    'getSessions' => {
        driver => 1,
        execute => sub {
            my ($driver) = @_;
            return $driver->{sessions};
        },
        parse  => sub {
            my ($driver, $ret) = @_;
            return [map { $_->{sessionId} } @$ret];
        },
    },
    #TODO not sure this is quite right
    'getCapabilities' => {
        driver => 1,
        execute => sub {
            my ($driver) = @_;
            return $driver->{capabilities};
        },
        parse => sub {
            my ($driver, $ret) = @_;
            return $ret;
        },
    },
    'setTimeout' => {
    },
    'setAsyncScriptTimeout' => {
    },
    'setImplicitWaitTimeout' => {
    },
    'quit' => {
    },
    'getCurrentWindowHandle' => {
    },
    'getWindowHandles' => {
    },
    'getWindowSize' => {
    },
    'getWindowPosition' => {
    },
    'maximizeWindow' => {
    },
    'setWindowSize' => {
    },
    'setWindowPosition' => {
    },
    'getCurrentUrl' => {
    },
    'get' => {
    },
    'goForward' => {
    },
    'goBack' => {
    },
    'refresh' => {
    },
    'executeScript' => {
    },
    'executeAsyncScript' => {
    },
    'screenshot' => {
    },
    'availableEngines' => {
    },
    'switchToFrame' => {
    },
    'switchToWindow' => {
    },
    'getAllCookies' => {
    },
    'addCookie' => {
    },
    'deleteAllCookies' => {
    },
    'deleteCookieNamed' => {
    },
    'getPageSource' => {
    },
    'getTitle' => {
    },
    'findElement' => {
    },
    'findElements' => {
    },
    'getActiveElement' => {
    },
    'describeElement' => {
    },
    'findChildElement' => {
    },
    'findChildElements' => {
    },
    'clickElement' => {
    },
    'submitElement' => {
    },
    'sendKeysToElement' => {
    },
    'sendKeysToActiveElement' => {
    },
    'sendModifier' => {
    },
    'isElementSelected' => {
    },
    'setElementSelected' => {
    },
    'toggleElement' => {
    },
    'isElementEnabled' => {
    },
    'getElementLocation' => {
    },
    'getElementLocationInView' => {
    },
    'getElementTagName' => {
    },
    'clearElement' => {
    },
    'getElementAttribute' => {
    },
    'elementEquals' => {
    },
    'isElementDisplayed' => {
    },
    'close' => {
    },
    'getElementSize' => {
    },
    'getElementText' => {
    },
    'getElementValueOfCssProperty' => {
    },
    'mouseMoveToLocation' => {
    },
    'getAlertText' => {
    },
    'sendKeysToPrompt' => {
    },
    'acceptAlert' => {
    },
    'dismissAlert' => {
    },
    'click' => {
    },
    'doubleClick' => {
    },
    'buttonDown' => {
    },
    'buttonUp' => {
    },
    'uploadFile' => {
    },
    'getLocalStorageItem' => {
    },
    'deleteLocalStorageItem' => {
    },
    'cacheStatus' => {
    },
    'setGeolocation' => {
    },
    'getGeolocation' => {
    },
    'getLog' => {
    },
    'getLogTypes' => {
    },
    'setOrientation' => {
    },
    'getOrientation' => {
    },

    # firefox extension
    'setContext' => {
    },
    'getContext' => {
    },

    # geckodriver workarounds
    'executeScriptGecko' => {
    },
    'executeAsyncScriptGecko' => {
    },

    # /session/:sessionId/local_storage
    # /session/:sessionId/local_storage/key/:key
    # /session/:sessionId/local_storage/size
    # /session/:sessionId/session_storage
    # /session/:sessionId/session_storage/key/:key
    # /session/:sessionId/session_storage/size


);

sub new {
    my $class = shift;
    return bless({}, $class);
}

# Act like S::R::C
sub parse_response {
    my ($driver, $command, $response) = @_;
    return $command_map{$command}{parse}->($driver,$response);
}

# Act like S::R::RR
sub request {
    my ($driver, $command, $args) = @_;
    return $command_map{$command}{execute}->($driver, $args);
}

sub needs_driver {
    my ($command) = @_;
    return $command_map{$command}{driver};
}
