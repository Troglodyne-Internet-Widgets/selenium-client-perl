package Selenium::Client::Commands;

use strict;
use warnings;

# Polyfill from Selenium 4's spec to JSONWire + Selenium 3

sub _toughshit {
    my ($session, $params, $cmd) = @_;
    # Maybe this is a bit on the nose? Should I tell them the truth (Selenium 4 is WORSE than its predecessors) and link to playwright.dev?
    die "Sorry, Selenium 4 does not support $cmd!  Try downgrading your browser, driver binary, Selenium JAR and so forth to something that understands JSONWire protocol, or Selenium 3."
}

sub _emit {
    my ($session, $ret) = @_;
    return $ret;
}
sub _emit_null_ok {
    my ($session, $ret) = @_;
    return !defined $ret;
}


sub _timeout {
    my ($session, $params) = @_;
    return $session->SetTimeouts(%$params);
}

sub _sess_uc {
    my ($session, $params, $cmd) = @_;
    $cmd = ucfirst($cmd);
    return $session->$cmd->($session, %$params);
}

my %command_map = (
    'status' => {
        driver => 1,
        execute => sub {
            my ($driver,$params) = @_;
            return $driver->Status();
        },
        parse  => sub {
            my ($driver, $ret) = @_;
            return $ret;
        },
    },
    'newSession' => {
        driver => 1,
        execute => sub {
            my ($driver, $params) = @_;
            foreach my $key (keys(%$params)) {
                #XXX may not be the smartest idea
                delete $params->{$key} unless $params->{$key};
            }

            my %in = %$params ? ( desiredCapabilities => $params ) : ();
            my @ret = $driver->NewSession( %in );
            return [@ret];
        },
        parse => sub {
            my ($driver, $ret) = @_;
            my ($capabilities, $session) = @$ret;
            return { capabilities => $capabilities, session => $session };
        },
    },
    'setTimeout' => {
        execute => \&_timeout,
        parse   => \&_emit,
    },
    'setAsyncScriptTimeout' => {
        execute => \&_timeout,
        parse   => \&_emit,
    },
    'setImplicitWaitTimeout' => {
        execute => \&_timeout,
        parse   => \&_emit,
    },
    'getTimeouts' => {
        execute => sub { 
            my ($session, $params) = @_;
            return $session->GetTimeouts();
        },
        parse   => \&_emit,
    },
    #TODO murder the driver object too
    'quit' => {
        execute => sub {
            my ($session, $params) = @_;
            return $session->DeleteSession( sessionid => $session->{sessionid} );
        },
        parse   => \&_emit_null_ok,
    },
    'getCurrentWindowHandle' => {
        execute => sub {
            my ($session, $params) = @_;
            return $session->GetWindowHandle( %$params );
        },
        parse   => \&_emit,
    },
    'getWindowHandles' => {
        execute => \&_sess_uc,
        parse   => \&_emit,
    },
    #TODO May require output filtering
    'getWindowSize' => {
        execute => sub {
            my ($session, $params) = @_;
            return $session->GetWindowRect( %$params );
        },
        parse   => \&_emit,
    },
    'getWindowPosition' => {
        execute => sub {
            my ($session, $params) = @_;
            return $session->GetWindowRect( %$params );
        },
        parse   => \&_emit,
    },
    'maximizeWindow' => {
        execute => \&_sess_uc,
        parse   => \&_emit_null_ok,
    },
    'maximizeWindow' => {
        execute => \&_sess_uc,
        parse   => \&_emit_null_ok,
    },
    'fullscreenWindow' => {
        execute => \&_sess_uc,
        parse   => \&_emit_null_ok,
    },
    'setWindowSize' => {
        execute => sub {
            my ($session, $params) = @_;
            return $session->SetWindowRect( %$params );
        },
        parse   => \&_emit_null_ok,
    },
    'setWindowPosition' => {
        execute => sub {
            my ($session, $params) = @_;
            return $session->SetWindowRect( %$params );
        },
        parse   => \&_emit_null_ok,
    },
    'getCurrentUrl' => {
        execute => \&_sess_uc,
        parse   => \&_emit,
    },
    'get' => {
        execute => sub { 
            my ($session, $params) = @_;
            return $session->NavigateTo( %$params );
        },
        parse   => \&_emit_null_ok,
    },
    'goForward' => {
        execute => sub { 
            my ($session, $params) = @_;
            return $session->Forward( %$params );
        },
        parse   => \&_emit_null_ok,
    },
    'goBack' => {
        execute => sub { 
            my ($session, $params) = @_;
            return $session->Back( %$params );
        },
        parse   => \&_emit_null_ok,
    },
    'refresh' => {
        execute => \&_sess_uc,
        parse   => \&_emit,
    },
    'executeScript' => {
        execute => \&_sess_uc,
        parse   => \&_emit,
    },
    'executeAsyncScript' => {
        execute => \&_sess_uc,
        parse   => \&_emit,
    },
    'screenshot' => {
        execute => sub {
            my ($session, $params) = @_;
            $session->TakeScreenshot(%$params);
        },
        parse => \&_emit,
    },
    'availableEngines' => {
        execute => \&_toughshit,
    },
    'switchToFrame' => {
        execute => \&_sess_uc,
        parse   => \&_emit_null_ok,
    },
    'switchToParentFrame' => {
        execute => \&_sess_uc,
        parse   => \&_emit_null_ok,
    },
    'switchToWindow' => {
        execute => \&_sess_uc,
        parse   => \&_emit_null_ok,
    },
    'getAllCookies' => {
        execute => \&_sess_uc,
        parse   => \&_emit,
    },
    'addCookie' => {
        execute => \&_sess_uc,
        parse   => \&_emit_null_ok,
    },
    'deleteAllCookies' => {
        execute => \&_sess_uc,
        parse   => \&_emit_null_ok,
    },
    'deleteCookieNamed' => {
        execute => \&_toughshit,
    },
    'getPageSource' => {
        execute => \&_sess_uc,
        parse   => \&_emit,
    },
    'getTitle' => {
        execute => \&_sess_uc,
        parse   => \&_emit,
    },
    'findElement' => {
        driver => 1,
        execute => sub {
            my ($driver, $params) = @_;
            my $element = $driver->session->FindElement( %$params );
            return bless( $element, $driver->webelement_class );
        },
        parse => \&_emit,
    },
    'findElements' => {
        driver => 1,
        execute => sub {
            my ($driver, $params) = @_;
            my @elements = $driver->session->FindElements( %$params );
            return map { bless( $_, $driver->webelement_class ) } @elements;
        },
        parse => \&_emit,
    },
    'getActiveElement' => {
        execute => \&_toughshit,
    },
    'describeElement' => {
        execute => \&_toughshit,
    },
    'findChildElement' => {
        execute => \&_toughshit,
    },
    'findChildElements' => {
        execute => \&_toughshit,
    },
    'clickElement' => {
        element => 1,
        execute => sub {
            my ($element) = @_;
            $element->ElementClick();
        },
        parse => \&_emit_null_ok,
    },
    # TODO polyfill as send enter?
    'submitElement' => {
        execute => \&_toughshit,
    },
    'sendKeysToElement' => {
        element => 1,
        execute => sub {
            my ($element, $params) = @_;
            $element->ElementSendKeys(%$params);
        },
        parse => \&_emit,
    },
    'sendKeysToActiveElement' => {
        execute => \&_toughshit,
    },
    'sendModifier' => {
        execute => \&_toughshit,
    },
    'isElementSelected' => {
        element => 1,
        execute => \&_sess_uc,
        parse   => \&_emit,
    },
    # TODO polyfill
    'setElementSelected' => {
        execute => \&_toughshit,
    },
    'toggleElement' => {
        execute => \&_toughshit,
    },
    'isElementEnabled' => {
        element => 1,
        execute => \&_sess_uc,
        parse   => \&_emit,
    },
    'getElementLocation' => {
        element => 1,
        execute => sub {
            my ($element, $params) = @_;
            return $element->GetElementRect(%$params);
        },
        parse  => \&_emit,
    },
    'getElementLocationInView' => {
        execute => \&_toughshit,
    },
    'getElementTagName' => {
        element => 1,
        execute => \&_sess_uc,
        parse   => \&_emit,
    },
    'clearElement' => {
        element => 1,
        execute => sub {
            my ($element) = @_;
            return $element->ElementClear();
        },
        parse   => \&_emit,
    },
    'getElementAttribute' => {
        element => 1,
        execute => \&_sess_uc,
        parse   => \&_emit,
    },
    # TODO polyfills
    'elementEquals' => {
        execute => \&_toughshit,
    },
    'isElementDisplayed' => {
        execute => \&_toughshit,
    },
    'close' => {
        execute => sub {
            my ($session, $params) = @_;
            $session->closeWindow(%$params);
        },
        parse   => \&_emit_null_ok,
    },
    'getElementSize' => {
        element => 1,
        execute => sub {
            my ($element, $params) = @_;
            return $element->GetElementRect(%$params);
        },
        parse  => \&_emit,
    },
    'getElementText' => {
        element => 1,
        execute => \&_sess_uc,
        parse   => \&_emit,
    },
    'getElementValueOfCssProperty' => {
        element => 1,
        execute => sub {
            my ($element, $params) = @_;
            return $element->GetElementCSSValue(%$params);
        },
        parse => \&_emit,
    },
    'mouseMoveToLocation' => {
        execute => \&_toughshit,
    },
    'getAlertText' => {
        execute => \&_sess_uc,
        parse   => \&_emit,
    },
    'sendKeysToPrompt' => {
        execute => sub {
            my ($session, $params) = @_;
            $session->SendAlertText(%$params);
        },
        parse => \&_emit_null_ok,
    },
    'acceptAlert' => {
        execute => \&_sess_uc,
        parse   => \&_emit_null_ok,
    },
    'dismissAlert' => {
        execute => \&_sess_uc,
        parse   => \&_emit_null_ok,
    },
    'click' => {
        execute => \&_toughshit,
    },
    'doubleClick' => {
        execute => \&_toughshit,
    },
    'buttonDown' => {
        execute => \&_toughshit,
    },
    'buttonUp' => {
        execute => \&_toughshit,
    },
    'uploadFile' => {
        execute => \&_toughshit,
    },
    'getLocalStorageItem' => {
        execute => \&_toughshit,
    },
    'deleteLocalStorageItem' => {
        execute => \&_toughshit,
    },
    'cacheStatus' => {
        execute => \&_toughshit,
    },
    'setGeolocation' => {
        execute => \&_toughshit,
    },
    'getGeolocation' => {
        execute => \&_toughshit,
    },
    'getLog' => {
        execute => \&_toughshit,
    },
    'getLogTypes' => {
        execute => \&_toughshit,
    },
    'setOrientation' => {
        execute => \&_toughshit,
    },
    'getOrientation' => {
        execute => \&_toughshit,
    },

    # firefox extension
    'setContext' => {
        execute => \&_toughshit,
    },
    'getContext' => {
        execute => \&_toughshit,
    },

    # geckodriver workarounds
    'executeScriptGecko' => {
        execute => \&_toughshit,
    },
    'executeAsyncScriptGecko' => {
        execute => \&_toughshit,
    },
);

sub new {
    my $class = shift;
    return bless({}, $class);
}

# Act like S::R::C
sub parse_response {
    my ($self, $driver, $command, $response) = @_;
    return $command_map{$command}{parse}->($driver,$response);
}

# Act like S::R::RR
sub request {
    my ($self, $driver, $command, $args) = @_;
    die "No such command $command" unless ref $command_map{$command} eq 'HASH';
    return $command_map{$command}{execute}->($driver, $args, $command);
}

sub needs_driver {
    my ($self,$command) = @_;
    return $command_map{$command}{driver};
}

sub needs_element {
    my ($self, $command) = @_;
    return $command_map{$command}{element};
}
