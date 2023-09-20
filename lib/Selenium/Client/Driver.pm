package Selenium::Client::Driver;

use strict;
use warnings;

no warnings qw{experimental};
use feature qw{signatures state};

# ABSTRACT: Drop-In replacement for Selenium::Remote::Driver that supports selenium 4

use Scalar::Util;
use Carp::Always;
use Archive::Zip qw( :ERROR_CODES );

use Selenium::Client;
use Selenium::Client::Commands;
use Selenium::Client::WebElement;
use Selenium::Client::WDKeys;

our %CURRENT_ACTION_CHAIN = ( actions => [] );
our $FORCE_WD3 = 0;

use constant FINDERS => {
    class             => 'class name',
    class_name        => 'class name',
    css               => 'css selector',
    id                => 'id',
    link              => 'link text',
    link_text         => 'link text',
    name              => 'name',
    partial_link_text => 'partial link text',
    tag_name          => 'tag name',
    xpath             => 'xpath',
};

=head1 SYNOPSIS

    use Selenium::Client::Driver;

    my $driver = Selenium::Client::Driver->new;
    $driver->get('http://www.google.com');
    print $driver->get_title();
    $driver->quit();

=cut

=head1 DESCRIPTION

(Mostly) drop-in replacement for Selenium::Remote::Driver which supports selenium 4.

See the documentation for Selenium::Remote::Driver for how to use this module unless otherwise noted below.

The primary difference here is that we do not support direct driver usage without intermediation by the SeleniumHQ JAR any longer.

Aside from that any of the has_* methods for object properties do not exist any longer, but they weren't documented anyways.

=cut

#Getters/Setters

sub _param ($self, $default, $param, $value=undef) {
    $self->{$param} //= $default;
    $self->{$param} = $value if defined $value;
    return $self->{$param};
}

sub driver ($self, $driver=undef) {
    return $self->_param(undef, 'driver', $driver);
}

sub base_url ($self,$url=undef) {
    return $self->_param('','base_url',$url);
}

sub remote_server_addr ($self, $addr=undef) {
    return $self->_param('localhost','remote_server_addr',$addr);
}

sub port ($self, $port=undef) {
    return $self->_param(4444,'port',$port);
}

sub browser_name($self, $name=undef) {
    return $self->_param('firefox', 'browser_name', $name);
}

sub platform($self, $platform=undef) {
    return $self->_param('ANY', 'platform', $platform);
}

sub version($self, $version=undef) {
    return $self->_param('', 'version', $version);
}

sub webelement_class ($self, $class=undef) {
    return $self->_param('Selenium::Client::WebElement', 'webelement_class', $class);
}

sub default_finder ($self, $finder=undef) {
    return $self->_param('xpath', 'default_finder', $finder);
}

sub session($self, $session=undef) {
    return $self->_param(undef, 'session', $session);
}

sub session_id ($self, $id=undef) {
    return $self->session->{sessionId};
}

sub remote_conn ($self, $conn=undef) {
    return $self->_param(undef, 'remote_conn', $conn);
}

sub error_handler($self, $handler=undef) {
    die "error handler must be subroutine ref" unless ref $handler eq 'CODE';
    return $self->_param(sub {}, 'error_handler', $handler);
}

sub ua ($self, $ua=undef) {
    return $self->_param(undef, 'ua', $ua);
}

sub commands($self) {
    $self->{commands} //= Selenium::Client::Commands->new;
    return $self->{commands};
}

sub auto_close($self, $ac=undef) {
    return $self->_param(1, 'auto_close', $ac);
}

# Only here for compatibility
sub pid {
    return $$;
}

#TODO these bools may need JSONizing
sub javascript( $self, $js=undef) {
    return $self->_param(1, 'javascript', $js);
}

sub accept_ssl_certs ($self, $ssl=undef) {
    return $self->_param(1, 'accept_ssl_certs', $ssl);
}

sub proxy ($self, $proxy=undef) {
    if ($proxy) {
        die "Proxy must be a hashref" unless ref $proxy eq 'HASH';
        if ( $proxy->{proxyType} =~ /^pac$/i ) {
            if ( not defined $proxy->{proxyAutoconfigUrl} ) {
                die "proxyAutoconfigUrl not provided\n";
            }
            elsif ( not( $proxy->{proxyAutoconfigUrl} =~ /^(http|file)/g ) ) {
                die
                  "proxyAutoconfigUrl should be of format http:// or file://";
            }

            if ( $proxy->{proxyAutoconfigUrl} =~ /^file/ ) {
                my $pac_url = $proxy->{proxyAutoconfigUrl};
                my $file    = $pac_url;
                $file =~ s{^file://}{};

                if ( !-e $file ) {
                    die "proxyAutoConfigUrl file does not exist: '$pac_url'";
                }
            }
        }
    }
    return $self->_param(undef, 'proxy', $proxy);
}

#TODO what the hell is the difference between these two in practice?
sub extra_capabilities($self, $caps=undef) {
    return $self->_param(undef, 'extra_capabilities', $caps);
}

sub desired_capabilities($self, $caps=undef) {
    return $self->_param(undef, 'desired_capabilities', $caps);
}

sub capabilities($self, $caps=undef) {
    return $self->_param(undef, 'desired_capabilities', $caps);
}

sub firefox_profile ($self, $profile=undef) {
    if ($profile) {
        unless ( Scalar::Util::blessed($profile) && $profile->isa('Selenium::Firefox::Profile') ) {
            die "firefox_profile must be a Selenium::Firefox::Profile";
        }
    }
    return $self->_param(undef, 'firefox_profile', $profile);
}

sub debug($self, $debug=undef) {
    return $self->_param(0, 'debug', $debug);
}

sub headless($self, $headless=0) {
    return $self->_param(0, 'headless', $headless);
}

sub inner_window_size( $self, $size=undef) {
    if (ref $size eq 'ARRAY') {
        die "inner_window_size must have two elements: [ height, width ]"
          unless scalar @$size == 2;

        foreach my $dim (@$size) {
            die 'inner_window_size only accepts integers, not: ' . $dim
              unless Scalar::Util::looks_like_number($dim);
        }

    }
    return $self->_param(undef, 'inner_window_size', $size);
}

# TODO do we care about this at all?
# At the time of writing, Geckodriver uses a different endpoint than
# the java bindings for executing synchronous and asynchronous
# scripts. As a matter of fact, Geckodriver does conform to the W3C
# spec, but as are bound to support both while the java bindings
# transition to full spec support, we need some way to handle the
# difference.
sub _execute_script_suffix ($self, $suffix=undef) {
    return $self->_param(undef, '_execute_script_suffix', $suffix);
}

#TODO generate find_element_by crap statically
#with 'Selenium::Remote::Finders';

sub new($class,%options) {
    my $self = bless(\%options, $class);


    if ( !$self->driver ) {
        if ( $self->desired_capabilities ) {
            $self->new_desired_session( $self->desired_capabilities );
        }
        else {
            # Connect to remote server & establish a new session
            $self->new_session( $self->extra_capabilities );
        }
    }

    if ( !( defined $self->session_id ) ) {
        die "Could not establish a session with the remote server\n";
    }
    if ( $self->inner_window_size ) {
        my $size = $self->inner_window_size;
        $self->set_inner_window_size(@$size);
    }

    #Set debug if needed
    $self->debug_on() if $self->debug;

    return $self;
}

sub new_from_caps($self, %args) {
    if ( not exists $args{desired_capabilities} ) {
        $args{desired_capabilities} = {};
    }
    return $self->new(%args);
}

#TODO do we need this?
sub DESTROY {
}

# This is an internal method used the Driver & is not supposed to be used by
# end user. This method is used by Driver to set up all the parameters
# (url & JSON), send commands & receive processed response from the server.
sub _execute_command($self, $res, $params={}) {
    use Data::Dumper;
    print Dumper($res,$params);
    print "Executing $res->{command}\n" if $self->{debug};
    my $resource = $self->commands->get_params($res);

    if (!$resource) {
        die "Couldn't retrieve command settings properly ".$res->{command}."\n";
    }
    my $macguffin = $self->commands->needs_driver( $res->{command} ) ? $self->driver : $self->session;
    local $@;
    eval {
        my $resp = $self->commands->request( $macguffin, $resource, $params );
        return $self->commands->parse_response( $macguffin, $resp );
    } or do {
        return $self->error_handler->( $macguffin, $@, $params ) if $self->error_handler;
        die $@;
    };
}

=head1 METHODS

=head2 new_session (extra_capabilities)

Make a new session on the server.
Called by new(), not intended for regular use.

Occaisonally handy for recovering from brower crashes.

DANGER DANGER DANGER

This will throw away your old session if you have not closed it!

DANGER DANGER DANGER

=cut

sub new_session($self, $extra_capabilities={}) {
    my $caps = {
        'platform'          => $self->platform,
        'javascriptEnabled' => $self->javascript,
        'version'           => $self->version // '',
        'acceptSslCerts'    => $self->accept_ssl_certs,
        %$extra_capabilities,
    };

    if ( defined $self->proxy ) {
        $caps->{proxy} = $self->proxy;
    }

    if ( $caps->{browserName} && $caps->{browserName} =~ /firefox/i
        && $self->firefox_profile )
    {
        $caps->{firefox_profile} =
          $self->firefox_profile->_encode;
    }

    my %options = ( driver => 'auto', browser => $self->browser_name, debug => $self->debug, headless => $self->headless, capabilities => $caps );

    return $self->_request_new_session(\%options);
}

=head2 new_desired_session(capabilities)

The same as new_session, here for compatibility

=cut

sub new_desired_session {
    my ( $self, $caps ) = @_;
    return $self->new_session($caps);
}

sub _request_new_session {
    my ( $self, $args ) = @_;

    my $driver = $self->driver();
    if (!$driver) {
        $driver = Selenium::Client->new( %$args );
        $self->driver($driver);
    }
    my $status = $driver->Status();
    die "Got bad status back from server!" unless $status;

    my $ret = $self->_execute_command('newSession', $args);
    my ($capabilities, $session) = @$ret;
    die "Failed to get caps back from newSession"    unless $capabilities->isa("Selenium::Capabilities");
    die "Failed to get session back from newSession" unless $session->isa("Selenium::Session");
    $self->session($session);
    $self->capabilities($capabilities);

    return $self;
}

=head2 is_webdriver_3, is_webdriver4

Guess which one is true, and which is false.
Here for compatibility.

=cut

sub is_webdriver_3 {
    return 0;
}

sub is_webdriver_4 {
    return 1;
}

=head2 debug_on

  Description:
    Turns on debugging mode and the driver will print extra info like request
    and response to stdout. Useful, when you want to see what is being sent to
    the server & what response you are getting back.

  Usage:
    $driver->debug_on;

=cut

sub debug_on($self) {
    $self->{debug} = 1;
    $self->driver->{debug} = 1;
}

=head2 debug_off

  Description:
    Turns off the debugging mode.

  Usage:
    $driver->debug_off;

=cut

sub debug_off {
    my ($self) = @_;
    $self->{debug} = 0;
    $self->driver->{debug} = 0;
}

=head2 get_sessions

  Description:
    Returns a list of the currently active sessions. Each session will be
    returned as an array of Hashes with the following keys:

    'id' : The session ID
    'capabilities: An object describing session's capabilities

  Output:
    Array of Hashes

  Usage:
    print Dumper $driver->get_sessions();

=cut

sub get_sessions {
    my ($self) = @_;
    my $res = { 'command' => 'getSessions' };
    return $self->_execute_command($res);
}

=head2 status

  Description:
    Query the server's current status. All server implementations
    should return two basic objects describing the server's current
    platform and when the server was built.

  Output:
    Hash ref

  Usage:
    print Dumper $driver->status;

=cut

sub status {
    my ($self) = @_;
    my $res = { 'command' => 'status' };
    return $self->_execute_command($res);
}

=head2 get_alert_text

 Description:
    Gets the text of the currently displayed JavaScript alert(), confirm()
    or prompt() dialog.

 Example
    my $string = $driver->get_alert_text;

=cut

sub get_alert_text {
    my ($self) = @_;
    my $res = { 'command' => 'getAlertText' };
    return $self->_execute_command($res);
}

=head2 send_keys_to_active_element

 Description:
    Send a sequence of key strokes to the active element. This command is
    similar to the send keys command in every aspect except the implicit
    termination: The modifiers are not released at the end of the call.
    Rather, the state of the modifier keys is kept between calls, so mouse
    interactions can be performed while modifier keys are depressed.

 Compatibility:
    On webdriver 3 servers, don't use this to send modifier keys; use send_modifier instead.

 Input: 1
    Required:
        {ARRAY | STRING} - Array of strings or a string.

 Usage:
    $driver->send_keys_to_active_element('abcd', 'efg');
    $driver->send_keys_to_active_element('hijk');

    or

    # include the WDKeys module
    use Selenium::Remote::WDKeys;
    $driver->send_keys_to_active_element(KEYS->{'space'}, KEYS->{'enter'});

=cut

sub send_keys_to_active_element {
    my ( $self, @strings ) = @_;

    if ( $self->{is_wd3}
        && !( grep { $self->browser_name eq $_ } qw{MicrosoftEdge} ) )
    {
        @strings = map { split( '', $_ ) } @strings;
        my @acts = map {
            (
                {
                    type  => 'keyDown',
                    value => $_,
                },
                {
                    type  => 'keyUp',
                    value => $_,
                }
              )
        } @strings;

        my $action = {
            actions => [
                {
                    id      => 'key',
                    type    => 'key',
                    actions => \@acts,
                }
            ]
        };
        return $self->general_action(%$action);
    }

    my $res    = { 'command' => 'sendKeysToActiveElement' };
    my $params = { 'value'   => \@strings, };
    return $self->_execute_command( $res, $params );
}

=head2 send_keys_to_alert

Synonymous with send_keys_to_prompt

=cut

sub send_keys_to_alert {
    return shift->send_keys_to_prompt(@_);
}

=head2 send_keys_to_prompt

 Description:
    Sends keystrokes to a JavaScript prompt() dialog.

 Input:
    {string} keys to send

 Example:
    $driver->send_keys_to_prompt('hello world');
  or
    ok($driver->get_alert_text eq 'Please Input your name','prompt appears');
    $driver->send_keys_to_alert("Larry Wall");
    $driver->accept_alert;

=cut

sub send_keys_to_prompt {
    my ( $self, $keys ) = @_;
    my $res    = { 'command' => 'sendKeysToPrompt' };
    my $params = { 'text'    => $keys };
    return $self->_execute_command( $res, $params );
}

=head2 accept_alert

 Description:
    Accepts the currently displayed alert dialog.  Usually, this is
    equivalent to clicking the 'OK' button in the dialog.

 Example:
    $driver->accept_alert;

=cut

sub accept_alert {
    my ($self) = @_;
    my $res = { 'command' => 'acceptAlert' };
    return $self->_execute_command($res);
}

=head2 dismiss_alert

 Description:
    Dismisses the currently displayed alert dialog. For comfirm()
    and prompt() dialogs, this is equivalent to clicking the
    'Cancel' button. For alert() dialogs, this is equivalent to
    clicking the 'OK' button.

 Example:
    $driver->dismiss_alert;

=cut

sub dismiss_alert {
    my ($self) = @_;
    my $res = { 'command' => 'dismissAlert' };
    return $self->_execute_command($res);
}

=head2 general_action

Provide an 'actions definition' hash to make webdriver use input devices.
Given the spec for the structure of this data is 'non normative',
it is left as an exercise to the reader what that means as to how to use this function.

That said, it seems most of the data looks something like this:

    $driver->general_action( actions => [{
        type => 'pointer|key|none|somethingElseSuperSpecialDefinedByYourBrowserDriver',
        id => MUST be mouse|key|none|other.  And by 'other' I mean anything else.  The first 3 are 'special' in that they are used in the global actions queue.
              If you want say, another mouse action to execute in parallel to other mouse actions (to simulate multi-touch, for example), call your action 'otherMouseAction' or something.
        parameters => {
            someOption => "basically these are global parameters used by all steps in the forthcoming "action chain".
        },
        actions => [
            {
                type => "keyUp|KeyDown if key, pointerUp|pointerDown|pointerMove|pointerCancel if pointer, pause if any type",
                key => A raw keycode or character from the keyboard if this is a key event,
                duration => how many 'ticks' this action should take, you probably want this to be 0 all of the time unless you are evading Software debounce.
                button => what number button if you are using a pointer (this sounds terribly like it might be re-purposed to be a joypad in the future sometime)
                origin => Point of Origin if moving a pointer around
                x => unit vector to travel along x-axis if pointerMove event
                y => unit vector to travel along y-axis if pointerMove event
            },
            ...
        ]
        },
        ...
        ]
    )

Only available on WebDriver3 capable selenium servers.

If you have called any legacy shim, such as mouse_move_to_location() previously, your actions passed will be appended to the existing actions queue.
Called with no arguments, it simply executes the existing action queue.

If you are looking for pre-baked action chains that aren't currently part of L<Selenium::Remote::Driver>,
consider L<Selenium::ActionChains>, which is shipped with this distribution instead.

=head3 COMPATIBILITY

Like most places, the WC3 standard is openly ignored by the driver binaries.
Generally an "actions" object will only accept:

    { type => ..., value => ... }

When using the direct drivers (E.G. Selenium::Chrome, Selenium::Firefox).
This is not documented anywhere but here, as far as I can tell.

=cut

sub general_action {
    my ( $self, %action ) = @_;

    _queue_action(%action);
    my $res = { 'command' => 'generalAction' };
    my $out = $self->_execute_command( $res, \%CURRENT_ACTION_CHAIN );
    %CURRENT_ACTION_CHAIN = ( actions => [] );
    return $out;
}

sub _queue_action {
    my (%action) = @_;
    if ( ref $action{actions} eq 'ARRAY' ) {
        foreach my $live_action ( @{ $action{actions} } ) {
            my $existing_action;
            foreach my $global_action ( @{ $CURRENT_ACTION_CHAIN{actions} } ) {
                if ( $global_action->{id} eq $live_action->{id} ) {
                    $existing_action = $global_action;
                    last;
                }
            }
            if ($existing_action) {
                push(
                    @{ $existing_action->{actions} },
                    @{ $live_action->{actions} }
                );
            }
            else {
                push( @{ $CURRENT_ACTION_CHAIN{actions} }, $live_action );
            }
        }
    }
}

=head2 release_general_action

Nukes *all* input device state (modifier key up/down, pointer button up/down, pointer location, and other device state) from orbit.
Call if you forget to do a *Up event in your provided action chains, or just to save time.

Also clears the current actions queue.

Only available on WebDriver3 capable selenium servers.

=cut

sub release_general_action {
    my ($self) = @_;
    my $res = { 'command' => 'releaseGeneralAction' };
    %CURRENT_ACTION_CHAIN = ( actions => [] );
    return $self->_execute_command($res);
}

=head2 mouse_move_to_location

 Description:
    Move the mouse by an offset of the specificed element. If no
    element is specified, the move is relative to the current mouse
    cursor. If an element is provided but no offset, the mouse will be
    moved to the center of the element. If the element is not visible,
    it will be scrolled into view.

 Compatibility:
    Due to limitations in the Webdriver 3 API, mouse movements have to be executed 'lazily' e.g. only right before a click() event occurs.
    This is because there is no longer any persistent mouse location state; mouse movements are now totally atomic.
    This has several problematic aspects; for one, I can't think of a way to both hover an element and then do another action relying on the element staying hover()ed,
    Aside from using javascript workarounds.

 Output:
    STRING -

 Usage:
    # element - the element to move to. If not specified or is null, the offset is relative to current position of the mouse.
    # xoffset - X offset to move to, relative to the top-left corner of the element. If not specified, the mouse will move to the middle of the element.
    # yoffset - Y offset to move to, relative to the top-left corner of the element. If not specified, the mouse will move to the middle of the element.

    print $driver->mouse_move_to_location(element => e, xoffset => x, yoffset => y);

=cut

sub mouse_move_to_location {
    my ( $self, %params ) = @_;
    $params{element} = $params{element}{id} if exists $params{element};

    if ( $self->{is_wd3}
        && !( grep { $self->browser_name eq $_ } qw{MicrosoftEdge} ) )
    {
        my $origin      = $params{element};
        my $move_action = {
            type     => "pointerMove",
            duration => 0,
            x        => $params{xoffset} // 0,
            y        => $params{yoffset} // 0,
        };
        $move_action->{origin} =
          { 'element-6066-11e4-a52e-4f735466cecf' => $origin }
          if $origin;

        _queue_action(
            actions => [
                {
                    type         => "pointer",
                    id           => 'mouse',
                    "parameters" => { "pointerType" => "mouse" },
                    actions      => [$move_action],
                }
            ]
        );
        return 1;
    }

    my $res = { 'command' => 'mouseMoveToLocation' };
    return $self->_execute_command( $res, \%params );
}

=head2 move_to

Synonymous with mouse_move_to_location

=cut

sub move_to {
    return shift->mouse_move_to_location(@_);
}

=head2 get_capabilities

 Description:
    Retrieve the capabilities of the specified session.

 Output:
    HASH of all the capabilities.

 Usage:
    my $capab = $driver->get_capabilities();
    print Dumper($capab);

=cut

sub get_capabilities {
    my $self = shift;
    my $res = { 'command' => 'getCapabilities' };
    return $self->_execute_command($res);
}

=head2 get_timeouts

  Description:
    Get the currently configured values (ms) for the page load, script and implicit timeouts.

  Compatibility:
    Only available on WebDriver3 enabled selenium servers.

  Usage:
    $driver->get_timeouts();

=cut

sub get_timeouts {
    my $self = shift;
    my $res = { 'command' => 'getTimeouts' };
    return $self->_execute_command( $res, {} );
}

=head2 set_timeout

 Description:
    Configure the amount of time that a particular type of operation can execute
    for before they are aborted and a |Timeout| error is returned to the client.

 Input:
    type - <STRING> - The type of operation to set the timeout for.
                      Valid values are:
                      "script"    : for script timeouts,
                      "implicit"  : for modifying the implicit wait timeout
                      "page load" : for setting a page load timeout.
    ms - <NUMBER> - The amount of time, in milliseconds, that time-limited
            commands are permitted to run.

 Usage:
    $driver->set_timeout('script', 1000);

=cut

sub set_timeout {
    my ( $self, $type, $ms ) = @_;
    if ( not defined $type ) {
        die "Expecting type";
    }
    $ms   = _coerce_timeout_ms($ms);
    $type = 'pageLoad'
      if $type eq 'page load'
      && $self->browser_name ne
      'MicrosoftEdge';    #XXX SHIM they changed the WC3 standard mid stream

    my $res    = { 'command' => 'setTimeout' };
    my $params = { $type     => $ms };

    #XXX edge still follows earlier versions of the WC3 standard
    if ( $self->browser_name eq 'MicrosoftEdge' ) {
        $params->{ms}   = $ms;
        $params->{type} = $type;
    }
    return $self->_execute_command( $res, $params );
}

=head2 set_async_script_timeout

 Description:
    Set the amount of time, in milliseconds, that asynchronous scripts executed
    by execute_async_script() are permitted to run before they are
    aborted and a |Timeout| error is returned to the client.

 Input:
    ms - <NUMBER> - The amount of time, in milliseconds, that time-limited
            commands are permitted to run.

 Usage:
    $driver->set_async_script_timeout(1000);

=cut

sub set_async_script_timeout {
    my ( $self, $ms ) = @_;

    return $self->set_timeout( 'script', $ms ) if $self->{is_wd3};

    $ms = _coerce_timeout_ms($ms);
    my $res    = { 'command' => 'setAsyncScriptTimeout' };
    my $params = { 'ms'      => $ms };
    return $self->_execute_command( $res, $params );
}

=head2 set_implicit_wait_timeout

 Description:
    Set the amount of time the driver should wait when searching for elements.
    When searching for a single element, the driver will poll the page until
    an element is found or the timeout expires, whichever occurs first.
    When searching for multiple elements, the driver should poll the page until
    at least one element is found or the timeout expires, at which point it
    will return an empty list. If this method is never called, the driver will
    default to an implicit wait of 0ms.

    This is exactly equivalent to calling L</set_timeout> with a type
    arg of C<"implicit">.

 Input:
    Time in milliseconds.

 Output:
    Server Response Hash with no data returned back from the server.

 Usage:
    $driver->set_implicit_wait_timeout(10);

=cut

sub set_implicit_wait_timeout {
    my ( $self, $ms ) = @_;
    return $self->set_timeout( 'implicit', $ms ) if $self->{is_wd3};

    $ms = _coerce_timeout_ms($ms);
    my $res    = { 'command' => 'setImplicitWaitTimeout' };
    my $params = { 'ms'      => $ms };
    return $self->_execute_command( $res, $params );
}

=head2 pause

 Description:
    Pause execution for a specified interval of milliseconds.

 Usage:
    $driver->pause(10000);  # 10 second delay
    $driver->pause();       #  1 second delay default

 DEPRECATED: consider using Time::HiRes instead.

=cut

sub pause {
    my $self = shift;
    my $timeout = ( shift // 1000 ) * 1000;
    usleep($timeout);
}

=head2 close

 Description:
    Close the current window.

 Usage:
    $driver->close();
 or
    #close a popup window
    my $handles = $driver->get_window_handles;
    $driver->switch_to_window($handles->[1]);
    $driver->close();
    $driver->switch_to_window($handles->[0]);

=cut

sub close {
    my $self = shift;
    my $res = { 'command' => 'close' };
    $self->_execute_command($res);
}

=head2 quit

 Description:
    DELETE the session, closing open browsers. We will try to call
    this on our down when we get destroyed, but in the event that we
    are demolished during global destruction, we will not be able to
    close the browser. For your own unattended and/or complicated
    tests, we recommend explicitly calling quit to make sure you're
    not leaving orphan browsers around.

    Note that as a Moo class, we use a subroutine called DEMOLISH that
    takes the place of DESTROY; for more information, see
    https://metacpan.org/pod/Moo#DEMOLISH.

 Usage:
    $driver->quit();

=cut

sub quit {
    my $self = shift;
    my $res = { 'command' => 'quit' };
    $self->_execute_command($res);
    $self->session_id(undef);
}

=head2 get_current_window_handle

 Description:
    Retrieve the current window handle.

 Output:
    STRING - the window handle

 Usage:
    print $driver->get_current_window_handle();

=cut

sub get_current_window_handle {
    my $self = shift;
    my $res = { 'command' => 'getCurrentWindowHandle' };
    return $self->_execute_command($res);
}

=head2 get_window_handles

 Description:
    Retrieve the list of window handles used in the session.

 Output:
    ARRAY of STRING - list of the window handles

 Usage:
    print Dumper $driver->get_window_handles;
 or
    # get popup, close, then back
    my $handles = $driver->get_window_handles;
    $driver->switch_to_window($handles->[1]);
    $driver->close;
    $driver->switch_to_window($handles->[0]);

=cut

sub get_window_handles {
    my $self = shift;
    my $res = { 'command' => 'getWindowHandles' };
    return $self->_execute_command($res);
}

=head2 get_window_size

 Description:
    Retrieve the window size

 Compatibility:
    The ability to get the size of arbitrary handles by passing input only exists in WebDriver2.
    You will have to switch to the window first going forward.

 Input:
    STRING - <optional> - window handle (default is 'current' window)

 Output:
    HASH - containing keys 'height' & 'width'

 Usage:
    my $window_size = $driver->get_window_size();
    print $window_size->{'height'}, $window_size->{'width'};

=cut

sub get_window_size {
    my ( $self, $window ) = @_;
    $window = ( defined $window ) ? $window : 'current';
    my $res = { 'command' => 'getWindowSize', 'window_handle' => $window };
    $res = { 'command' => 'getWindowRect', handle => $window }
      if $self->{is_wd3};
    return $self->_execute_command($res);
}

=head2 get_window_position

 Description:
    Retrieve the window position

 Compatibility:
    The ability to get the size of arbitrary handles by passing input only exists in WebDriver2.
    You will have to switch to the window first going forward.

 Input:
    STRING - <optional> - window handle (default is 'current' window)

 Output:
    HASH - containing keys 'x' & 'y'

 Usage:
    my $window_size = $driver->get_window_position();
    print $window_size->{'x'}, $window_size->('y');

=cut

sub get_window_position {
    my ( $self, $window ) = @_;
    $window = ( defined $window ) ? $window : 'current';
    my $res = { 'command' => 'getWindowPosition', 'window_handle' => $window };
    $res = { 'command' => 'getWindowRect', handle => $window }
      if $self->{is_wd3};
    return $self->_execute_command($res);
}

=head2 get_current_url

 Description:
    Retrieve the url of the current page

 Output:
    STRING - url

 Usage:
    print $driver->get_current_url();

=cut

sub get_current_url {
    my $self = shift;
    my $res = { 'command' => 'getCurrentUrl' };
    return $self->_execute_command($res);
}

=head2 navigate

 Description:
    Navigate to a given url. This is same as get() method.

 Input:
    STRING - url

 Usage:
    $driver->navigate('http://www.google.com');

=cut

sub navigate {
    my ( $self, $url ) = @_;
    $self->get($url);
}

=head2 get

 Description:
    Navigate to a given url

 Input:
    STRING - url

 Usage:
    $driver->get('http://www.google.com');

=cut

sub get {
    my ( $self, $url ) = @_;

    if ( $self->base_url && $url !~ m|://| ) {
        $url =~ s|^/||;
        $url = $self->base_url . "/" . $url;
    }

    my $res    = { 'command' => 'get' };
    my $params = { 'url'     => $url };
    return $self->_execute_command( $res, $params );
}

=head2 get_title

 Description:
    Get the current page title

 Output:
    STRING - Page title

 Usage:
    print $driver->get_title();

=cut

sub get_title {
    my $self = shift;
    my $res = { 'command' => 'getTitle' };
    return $self->_execute_command($res);
}

=head2 go_back

 Description:
    Equivalent to hitting the back button on the browser.

 Usage:
    $driver->go_back();

=cut

sub go_back {
    my $self = shift;
    my $res = { 'command' => 'goBack' };
    return $self->_execute_command($res);
}

=head2 go_forward

 Description:
    Equivalent to hitting the forward button on the browser.

 Usage:
    $driver->go_forward();

=cut

sub go_forward {
    my $self = shift;
    my $res = { 'command' => 'goForward' };
    return $self->_execute_command($res);
}

=head2 refresh

 Description:
    Reload the current page.

 Usage:
    $driver->refresh();

=cut

sub refresh {
    my $self = shift;
    my $res = { 'command' => 'refresh' };
    return $self->_execute_command($res);
}

=head2 has_javascript

 Description:
    returns true if javascript is enabled in the driver.

 Compatibility:
    Can't be false on WebDriver 3.

 Usage:
    if ($driver->has_javascript) { ...; }

=cut

sub has_javascript {
    my $self = shift;
    return int( $self->javascript );
}

=head2 execute_async_script

 Description:
    Inject a snippet of JavaScript into the page for execution in the context
    of the currently selected frame. The executed script is assumed to be
    asynchronous and must signal that is done by invoking the provided
    callback, which is always provided as the final argument to the function.
    The value to this callback will be returned to the client.

    Asynchronous script commands may not span page loads. If an unload event
    is fired while waiting for a script result, an error should be returned
    to the client.

 Input: 2 (1 optional)
    Required:
        STRING - Javascript to execute on the page
    Optional:
        ARRAY - list of arguments that need to be passed to the script.

 Output:
    {*} - Varied, depending on the type of result expected back from the script.

 Usage:
    my $script = q{
        var arg1 = arguments[0];
        var callback = arguments[arguments.length-1];
        var elem = window.document.findElementById(arg1);
        callback(elem);
    };
    my $elem = $driver->execute_async_script($script,'myid');
    $elem->click;

=cut

sub execute_async_script {
    my ( $self, $script, @args ) = @_;
    if ( $self->has_javascript ) {
        if ( not defined $script ) {
            die 'No script provided';
        }
        my $res =
          { 'command' => 'executeAsyncScript' . $self->_execute_script_suffix };

        # Check the args array if the elem obj is provided & replace it with
        # JSON representation
        for ( my $i = 0 ; $i < @args ; $i++ ) {
            if ( Scalar::Util::blessed( $args[$i] )
                and $args[$i]->isa('Selenium::Remote::WebElement') )
            {
                if ( $self->{is_wd3} ) {
                    $args[$i] =
                      { 'element-6066-11e4-a52e-4f735466cecf' =>
                          ( $args[$i] )->{id} };
                }
                else {
                    $args[$i] = { 'ELEMENT' => ( $args[$i] )->{id} };
                }
            }
        }

        my $params = { 'script' => $script, 'args' => \@args };
        my $ret = $self->_execute_command( $res, $params );

        # replace any ELEMENTS with WebElement
        if (    ref($ret)
            and ( ref($ret) eq 'HASH' )
            and $self->_looks_like_element($ret) )
        {
            $ret = $self->webelement_class->new(
                id     => $ret,
                driver => $self
            );
        }
        return $ret;
    }
    else {
        die 'Javascript is not enabled on remote driver instance.';
    }
}

=head2 execute_script

 Description:
    Inject a snippet of JavaScript into the page and return its result.
    WebElements that should be passed to the script as an argument should be
    specified in the arguments array as WebElement object. Likewise,
    any WebElements in the script result will be returned as WebElement object.

 Input: 2 (1 optional)
    Required:
        STRING - Javascript to execute on the page
    Optional:
        ARRAY - list of arguments that need to be passed to the script.

 Output:
    {*} - Varied, depending on the type of result expected back from the script.

 Usage:
    my $script = q{
        var arg1 = arguments[0];
        var elem = window.document.findElementById(arg1);
        return elem;
    };
    my $elem = $driver->execute_script($script,'myid');
    $elem->click;

=cut

sub execute_script {
    my ( $self, $script, @args ) = @_;
    if ( $self->has_javascript ) {
        if ( not defined $script ) {
            die 'No script provided';
        }
        my $res =
          { 'command' => 'executeScript' . $self->_execute_script_suffix };

        # Check the args array if the elem obj is provided & replace it with
        # JSON representation
        for ( my $i = 0 ; $i < @args ; $i++ ) {
            if ( Scalar::Util::blessed( $args[$i] )
                and $args[$i]->isa('Selenium::Remote::WebElement') )
            {
                if ( $self->{is_wd3} ) {
                    $args[$i] =
                      { 'element-6066-11e4-a52e-4f735466cecf' =>
                          ( $args[$i] )->{id} };
                }
                else {
                    $args[$i] = { 'ELEMENT' => ( $args[$i] )->{id} };
                }
            }
        }

        my $params = { 'script' => $script, 'args' => [@args] };
        my $ret = $self->_execute_command( $res, $params );

        return $self->_convert_to_webelement($ret);
    }
    else {
        die 'Javascript is not enabled on remote driver instance.';
    }
}

# _looks_like_element
# An internal method to check if a return value might be an element

sub _looks_like_element {
    my ( $self, $maybe_element ) = @_;

    return (
             exists $maybe_element->{ELEMENT}
          or exists $maybe_element->{'element-6066-11e4-a52e-4f735466cecf'}
    );
}

# _convert_to_webelement
# An internal method used to traverse a data structure
# and convert any ELEMENTS with WebElements

sub _convert_to_webelement {
    my ( $self, $ret ) = @_;

    if ( ref($ret) and ( ref($ret) eq 'HASH' ) ) {
        if ( $self->_looks_like_element($ret) ) {

            # replace an ELEMENT with WebElement
            return $self->webelement_class->new(
                id     => $ret,
                driver => $self
            );
        }

        my %hash;
        foreach my $key ( keys %$ret ) {
            $hash{$key} = $self->_convert_to_webelement( $ret->{$key} );
        }
        return \%hash;
    }

    if ( ref($ret) and ( ref($ret) eq 'ARRAY' ) ) {
        my @array = map { $self->_convert_to_webelement($_) } @$ret;
        return \@array;
    }

    return $ret;
}

=head2 screenshot

 Description:
    Get a screenshot of the current page as a base64 encoded image.
    Optionally pass {'full' => 1} as argument to take a full screenshot and not
    only the viewport. (Works only with firefox and geckodriver >= 0.24.0)

 Output:
    STRING - base64 encoded image

 Usage:
    print $driver->screenshot();
    print $driver->screenshot({'full' => 1});

To conveniently write the screenshot to a file, see L</capture_screenshot>.

=cut

sub screenshot {
    my ($self, $params) = @_;
    $params //= { full => 0 };

    die "Full page screenshot only supported on geckodriver" if $params->{full} && ( $self->{browser_name} ne 'firefox' );

    my $res = { 'command' => $params->{'full'} == 1 ? 'mozScreenshotFull' : 'screenshot' };
    return $self->_execute_command($res);
}

=head2 capture_screenshot

 Description:
    Capture a screenshot and save as a PNG to provided file name.
    (The method is compatible with the WWW::Selenium method of the same name)
    Optionally pass {'full' => 1} as second argument to take a full screenshot
    and not only the viewport. (Works only with firefox and geckodriver >= 0.24.0)

 Output:
    TRUE - (Screenshot is written to file)

 Usage:
    $driver->capture_screenshot($filename);
    $driver->capture_screenshot($filename, {'full' => 1});

=cut

sub capture_screenshot {
    my ( $self, $filename, $params ) = @_;
    die '$filename is required' unless $filename;

    open( my $fh, '>', $filename );
    binmode $fh;
    print $fh MIME::Base64::decode_base64( $self->screenshot($params) );
    CORE::close $fh;
    return 1;
}

=head2 available_engines

 Description:
    List all available engines on the machine. To use an engine, it has to be present in this list.

 Compatibility:
    Does not appear to be available on Webdriver3 enabled selenium servers.

 Output:
    {Array.<string>} A list of available engines

 Usage:
    print Dumper $driver->available_engines;

=cut

#TODO emulate behavior on wd3?
#grep { eval { Selenium::Remote::Driver->new( browser => $_ ) } } (qw{firefox MicrosoftEdge chrome opera safari htmlunit iphone phantomjs},'internet_explorer');
#might do the trick
sub available_engines {
    my ($self) = @_;
    my $res = { 'command' => 'availableEngines' };
    return $self->_execute_command($res);
}

=head2 switch_to_frame

 Description:
    Change focus to another frame on the page. If the frame ID is null, the
    server will switch to the page's default content. You can also switch to a
    WebElement, for e.g. you can find an iframe using find_element & then
    provide that as an input to this method. Also see e.g.

 Input: 1
    Required:
        {STRING | NUMBER | NULL | WebElement} - ID of the frame which can be one of the three
                                   mentioned.

 Usage:
    $driver->switch_to_frame('frame_1');
    or
    $driver->switch_to_frame($driver->find_element('iframe', 'tag_name'));

=head3 COMPATIBILITY

Chromedriver will vomit if you pass anything but a webElement, so you probably should do that from now on.

=cut

sub switch_to_frame {
    my ( $self, $id ) = @_;

    my $params;
    my $res = { 'command' => 'switchToFrame' };

    if ( ref $id eq $self->webelement_class ) {
        if ( $self->{is_wd3} ) {
            $params =
              { 'id' =>
                  { 'element-6066-11e4-a52e-4f735466cecf' => $id->{'id'} } };
        }
        else {
            $params = { 'id' => { 'ELEMENT' => $id->{'id'} } };
        }
    }
    else {
        $params = { 'id' => $id };
    }
    return $self->_execute_command( $res, $params );
}

=head2 switch_to_parent_frame

Webdriver 3 equivalent of calling switch_to_frame with no arguments (e.g. NULL frame).
This is actually called in that case, supposing you are using WD3 capable servers now.

=cut

sub switch_to_parent_frame {
    my ($self) = @_;
    my $res = { 'command' => 'switchToParentFrame' };
    return $self->_execute_command($res);
}

=head2 switch_to_window

 Description:
    Change focus to another window. The window to change focus to may
    be specified by its server assigned window handle, or by the value
    of the page's window.name attribute.

    If you wish to use the window name as the target, you'll need to
    have set C<window.name> on the page either in app code or via
    L</execute_script>, or pass a name as the second argument to the
    C<window.open()> function when opening the new window. Note that
    the window name used here has nothing to do with the window title,
    or the C<< <title> >> element on the page.

    Otherwise, use L</get_window_handles> and select a
    Webdriver-generated handle from the output of that function.

 Input: 1
    Required:
        STRING - Window handle or the Window name

 Usage:
    $driver->switch_to_window('MY Homepage');
 or
    # close a popup window and switch back
    my $handles = $driver->get_window_handles;
    $driver->switch_to_window($handles->[1]);
    $driver->close;
    $driver->switch_to_window($handles->[0]);

=cut

sub switch_to_window {
    my ( $self, $name ) = @_;
    if ( not defined $name ) {
        return 'Window name not provided';
    }
    my $res = { 'command' => 'switchToWindow' };
    my $params = { 'name' => $name, 'handle' => $name };
    return $self->_execute_command( $res, $params );
}

=head2 set_window_position

 Description:
    Set the position (on screen) where you want your browser to be displayed.

 Compatibility:
    In webDriver 3 enabled selenium servers, you may only operate on the focused window.
    As such, the window handle argument below will be ignored in this context.

 Input:
    INT - x co-ordinate
    INT - y co-ordinate
    STRING - <optional> - window handle (default is 'current' window)

 Output:
    BOOLEAN - Success or failure

 Usage:
    $driver->set_window_position(50, 50);

=cut

sub set_window_position {
    my ( $self, $x, $y, $window ) = @_;
    $window = ( defined $window ) ? $window : 'current';
    if ( not defined $x and not defined $y ) {
        die "X & Y co-ordinates are required";
    }
    die qq{Error: In set_window_size, argument x "$x" isn't numeric}
      unless Scalar::Util::looks_like_number($x);
    die qq{Error: In set_window_size, argument y "$y" isn't numeric}
      unless Scalar::Util::looks_like_number($y);
    $x +=
      0;  # convert to numeric if a string, otherwise they'll be sent as strings
    $y += 0;
    my $res = { 'command' => 'setWindowPosition', 'window_handle' => $window };
    my $params = { 'x' => $x, 'y' => $y };
    if ( $self->{is_wd3} ) {
        $res = { 'command' => 'setWindowRect', handle => $window };
    }
    my $ret = $self->_execute_command( $res, $params );
    return $ret ? 1 : 0;
}

=head2 set_window_size

 Description:
    Set the size of the browser window

 Compatibility:
    In webDriver 3 enabled selenium servers, you may only operate on the focused window.
    As such, the window handle argument below will be ignored in this context.

 Input:
    INT - height of the window
    INT - width of the window
    STRING - <optional> - window handle (default is 'current' window)

 Output:
    BOOLEAN - Success or failure

 Usage:
    $driver->set_window_size(640, 480);

=cut

sub set_window_size {
    my ( $self, $height, $width, $window ) = @_;
    $window = ( defined $window ) ? $window : 'current';
    if ( not defined $height and not defined $width ) {
        die "height & width of browser are required";
    }
    die qq{Error: In set_window_size, argument height "$height" isn't numeric}
      unless Scalar::Util::looks_like_number($height);
    die qq{Error: In set_window_size, argument width "$width" isn't numeric}
      unless Scalar::Util::looks_like_number($width);
    $height +=
      0;  # convert to numeric if a string, otherwise they'll be sent as strings
    $width += 0;
    my $res = { 'command' => 'setWindowSize', 'window_handle' => $window };
    my $params = { 'height' => $height, 'width' => $width };
    if ( $self->{is_wd3} ) {
        $res = { 'command' => 'setWindowRect', handle => $window };
    }
    my $ret = $self->_execute_command( $res, $params );
    return $ret ? 1 : 0;
}

=head2 maximize_window

 Description:
    Maximizes the browser window

 Compatibility:
    In webDriver 3 enabled selenium servers, you may only operate on the focused window.
    As such, the window handle argument below will be ignored in this context.

    Also, on chromedriver maximize is actually just setting the window size to the screen's
    available height and width.

 Input:
    STRING - <optional> - window handle (default is 'current' window)

 Output:
    BOOLEAN - Success or failure

 Usage:
    $driver->maximize_window();

=cut

sub maximize_window {
    my ( $self, $window ) = @_;

    $window = ( defined $window ) ? $window : 'current';
    my $res = { 'command' => 'maximizeWindow', 'window_handle' => $window };
    my $ret = $self->_execute_command($res);
    return $ret ? 1 : 0;
}

=head2 minimize_window

 Description:
    Minimizes the currently focused browser window (webdriver3 only)

 Output:
    BOOLEAN - Success or failure

 Usage:
    $driver->minimize_window();

=cut

sub minimize_window {
    my ( $self, $window ) = @_;
    $window = ( defined $window ) ? $window : 'current';
    my $res = { 'command' => 'minimizeWindow', 'window_handle' => $window };
    my $ret = $self->_execute_command($res);
    return $ret ? 1 : 0;
}

=head2 fullscreen_window

 Description:
    Fullscreens the currently focused browser window (webdriver3 only)

 Output:
    BOOLEAN - Success or failure

 Usage:
    $driver->fullscreen_window();

=cut

sub fullscreen_window {
    my ( $self, $window ) = @_;
    $window = ( defined $window ) ? $window : 'current';
    my $res = { 'command' => 'fullscreenWindow', 'window_handle' => $window };
    my $ret = $self->_execute_command($res);
    return $ret ? 1 : 0;
}

=head2 get_all_cookies

 Description:
    Retrieve all cookies visible to the current page. Each cookie will be
    returned as a HASH reference with the following keys & their value types:

    'name' - STRING
    'value' - STRING
    'path' - STRING
    'domain' - STRING
    'secure' - BOOLEAN

 Output:
    ARRAY of HASHES - list of all the cookie hashes

 Usage:
    print Dumper($driver->get_all_cookies());

=cut

sub get_all_cookies {
    my ($self) = @_;
    my $res = { 'command' => 'getAllCookies' };
    return $self->_execute_command($res);
}

=head2 add_cookie

 Description:
    Set a cookie on the domain.

 Input: 2 (4 optional)
    Required:
        'name'   - STRING
        'value'  - STRING

    Optional:
        'path'   - STRING
        'domain' - STRING
        'secure'   - BOOLEAN - default false.
        'httponly' - BOOLEAN - default false.
        'expiry'   - TIME_T  - default 20 years in the future

 Usage:
    $driver->add_cookie('foo', 'bar', '/', '.google.com', 0, 1)

=cut

sub add_cookie {
    my ( $self, $name, $value, $path, $domain, $secure, $httponly, $expiry ) =
      @_;

    if (   ( not defined $name )
        || ( not defined $value ) )
    {
        die "Missing parameters";
    }

    my $res        = { 'command' => 'addCookie' };
    my $params = {
        'cookie' => {
            'name'   => $name,
            'value'  => $value,
            'path'   => $path,
            'secure' => $secure,
        }
    };
    $params->{cookie}->{domain}     = $domain   if $domain;
    $params->{cookie}->{'httponly'} = $httponly if $httponly;
    $params->{cookie}->{'expiry'}   = $expiry   if $expiry;

    return $self->_execute_command( $res, $params );
}

=head2 delete_all_cookies

 Description:
    Delete all cookies visible to the current page.

 Usage:
    $driver->delete_all_cookies();

=cut

sub delete_all_cookies {
    my ($self) = @_;
    my $res = { 'command' => 'deleteAllCookies' };
    return $self->_execute_command($res);
}

=head2 get_cookie_named

Basically get only the cookie with the provided name.
Probably preferable to pick it out of the list unless you expect a *really* long list.

 Input:
    Cookie Name - STRING

Returns cookie definition hash, much like the elements in get_all_cookies();

  Compatibility:
    Only available on webdriver3 enabled selenium servers.

=cut

sub get_cookie_named {
    my ( $self, $cookie_name ) = @_;
    my $res = { 'command' => 'getCookieNamed', 'name' => $cookie_name };
    return $self->_execute_command($res);
}

=head2 delete_cookie_named

 Description:
    Delete the cookie with the given name. This command will be a no-op if there
    is no such cookie visible to the current page.

 Input: 1
    Required:
        STRING - name of cookie to delete

 Usage:
    $driver->delete_cookie_named('foo');

=cut

sub delete_cookie_named {
    my ( $self, $cookie_name ) = @_;
    if ( not defined $cookie_name ) {
        die "Cookie name not provided";
    }
    my $res = { 'command' => 'deleteCookieNamed', 'name' => $cookie_name };
    return $self->_execute_command($res);
}

=head2 get_page_source

 Description:
    Get the current page source.

 Output:
    STRING - The page source.

 Usage:
    print $driver->get_page_source();

=cut

sub get_page_source {
    my ($self) = @_;
    my $res = { 'command' => 'getPageSource' };
    return $self->_execute_command($res);
}

=head2 find_element

 Description:
    Search for an element on the page, starting from the document
    root. The located element will be returned as a WebElement
    object. If the element cannot be found, we will CROAK, killing
    your script. If you wish for a warning instead, use the
    parameterized version of the finders:

        find_element_by_class
        find_element_by_class_name
        find_element_by_css
        find_element_by_id
        find_element_by_link
        find_element_by_link_text
        find_element_by_name
        find_element_by_partial_link_text
        find_element_by_tag_name
        find_element_by_xpath

    These functions all take a single STRING argument: the locator
    search target of the element you want. If the element is found, we
    will receive a WebElement. Otherwise, we will return 0. Note that
    invoking methods on 0 will of course kill your script.

 Input: 2 (1 optional)
    Required:
        STRING - The search target.
    Optional:
        STRING - Locator scheme to use to search the element, available schemes:
                 {class, class_name, css, id, link, link_text, partial_link_text,
                  tag_name, name, xpath}
                 Defaults to 'xpath' if not configured global during instantiation.

 Output:
    Selenium::Remote::WebElement - WebElement Object
        (This could be a subclass of L<Selenium::Remote::WebElement> if C<webelement_class> was set.

 Usage:
    $driver->find_element("//input[\@name='q']");

=cut

sub find_element {
    my ( $self, $query, $method ) = @_;
    if ( not defined $query ) {
        die 'Search string to find element not provided.';
    }

    my $res = { 'command' => 'findElement' };
    my $params = $self->_build_find_params( $method, $query );
    my $ret_data = eval { $self->_execute_command( $res, $params ); };
    if ($@) {
        if ( $@ =~
/(An element could not be located on the page using the given search parameters)/
          )
        {
            # give details on what element wasn't found
            $@ = "$1: $query,$params->{using}";
            die $@;
        }
        else {
            # re throw if the exception wasn't what we expected
            die $@;
        }
    }
    return $self->webelement_class->new(
        id     => $ret_data,
        driver => $self
    );
}

=head2 find_elements

 Description:
    Search for multiple elements on the page, starting from the document root.
    The located elements will be returned as an array of WebElement object.

 Input: 2 (1 optional)
    Required:
        STRING - The search target.
    Optional:
        STRING - Locator scheme to use to search the element, available schemes:
                 {class, class_name, css, id, link, link_text, partial_link_text,
                  tag_name, name, xpath}
                 Defaults to 'xpath' if not configured global during instantiation.

 Output:
    ARRAY or ARRAYREF of WebElement Objects

 Usage:
    $driver->find_elements("//input");

=cut

sub find_elements {
    my ( $self, $query, $method ) = @_;
    if ( not defined $query ) {
        die 'Search string to find element not provided.';
    }

    my $res = { 'command' => 'findElements' };
    my $params = $self->_build_find_params( $method, $query );
    my $ret_data = eval { $self->_execute_command( $res, $params ); };
    if ($@) {
        if ( $@ =~
/(An element could not be located on the page using the given search parameters)/
          )
        {
            # give details on what element wasn't found
            $@ = "$1: $query,$params->{using}";
            die $@;
        }
        else {
            # re throw if the exception wasn't what we expected
            die $@;
        }
    }
    my $elem_obj_arr = [];
    foreach (@$ret_data) {
        push(
            @$elem_obj_arr,
            $self->webelement_class->new(
                id     => $_,
                driver => $self
            )
        );
    }
    return wantarray ? @{$elem_obj_arr} : $elem_obj_arr;
}

=head2 find_child_element

 Description:
    Search for an element on the page, starting from the identified element. The
    located element will be returned as a WebElement object.

 Input: 3 (1 optional)
    Required:
        Selenium::Remote::WebElement - WebElement object from where you want to
                                       start searching.
        STRING - The search target. (Do not use a double whack('//')
                 in an xpath to search for a child element
                 ex: '//option[@id="something"]'
                 instead use a dot whack ('./')
                 ex: './option[@id="something"]')
    Optional:
        STRING - Locator scheme to use to search the element, available schemes:
                 {class, class_name, css, id, link, link_text, partial_link_text,
                  tag_name, name, xpath}
                 Defaults to 'xpath' if not configured global during instantiation.

 Output:
    WebElement Object

 Usage:
    my $elem1 = $driver->find_element("//select[\@name='ned']");
    # note the usage of ./ when searching for a child element instead of //
    my $child = $driver->find_child_element($elem1, "./option[\@value='es_ar']");

=cut

sub find_child_element {
    my ( $self, $elem, $query, $method ) = @_;
    if ( ( not defined $elem ) || ( not defined $query ) ) {
        die "Missing parameters";
    }
    my $res = { 'command' => 'findChildElement', 'id' => $elem->{id} };
    my $params = $self->_build_find_params( $method, $query );
    my $ret_data = eval { $self->_execute_command( $res, $params ); };
    if ($@) {
        if ( $@ =~
/(An element could not be located on the page using the given search parameters)/
          )
        {
            # give details on what element wasn't found
            $@ = "$1: $query,$params->{using}";
            die $@;
        }
        else {
            # re throw if the exception wasn't what we expected
            die $@;
        }
    }
    return $self->webelement_class->new(
        id     => $ret_data,
        driver => $self
    );
}

=head2 find_child_elements

 Description:
    Search for multiple element on the page, starting from the identified
    element. The located elements will be returned as an array of WebElement
    objects.

 Input: 3 (1 optional)
    Required:
        Selenium::Remote::WebElement - WebElement object from where you want to
                                       start searching.
        STRING - The search target.
    Optional:
        STRING - Locator scheme to use to search the element, available schemes:
                 {class, class_name, css, id, link, link_text, partial_link_text,
                  tag_name, name, xpath}
                 Defaults to 'xpath' if not configured global during instantiation.

 Output:
    ARRAY of WebElement Objects.

 Usage:
    my $elem1 = $driver->find_element("//select[\@name='ned']");
    # note the usage of ./ when searching for a child element instead of //
    my $child = $driver->find_child_elements($elem1, "./option");

=cut

sub find_child_elements {
    my ( $self, $elem, $query, $method ) = @_;
    if ( ( not defined $elem ) || ( not defined $query ) ) {
        die "Missing parameters";
    }

    my $res = { 'command' => 'findChildElements', 'id' => $elem->{id} };
    my $params = $self->_build_find_params( $method, $query );
    my $ret_data = eval { $self->_execute_command( $res, $params ); };
    if ($@) {
        if ( $@ =~
/(An element could not be located on the page using the given search parameters)/
          )
        {
            # give details on what element wasn't found
            $@ = "$1: $query,$params->{using}";
            die $@;
        }
        else {
            # re throw if the exception wasn't what we expected
            die $@;
        }
    }
    my $elem_obj_arr = [];
    my $i            = 0;
    foreach (@$ret_data) {
        $elem_obj_arr->[$i] = $self->webelement_class->new(
            id     => $_,
            driver => $self
        );
        $i++;
    }
    return wantarray ? @{$elem_obj_arr} : $elem_obj_arr;
}

=head2 find_element_by_class

See L</find_element>.

=head2 find_element_by_class_name

See L</find_element>.

=head2 find_element_by_css

See L</find_element>.

=head2 find_element_by_id

See L</find_element>.

=head2 find_element_by_link

See L</find_element>.

=head2 find_element_by_link_text

See L</find_element>.

=head2 find_element_by_name

See L</find_element>.

=head2 find_element_by_partial_link_text

See L</find_element>.

=head2 find_element_by_tag_name

See L</find_element>.

=head2 find_element_by_xpath

See L</find_element>.

=head2 get_active_element

 Description:
    Get the element on the page that currently has focus.. The located element
    will be returned as a WebElement object.

 Output:
    WebElement Object

 Usage:
    $driver->get_active_element();

=cut

sub _build_find_params {
    my ( $self, $method, $query ) = @_;

    my $using = $self->_build_using($method);

    # geckodriver doesn't accept name as a valid selector
    if ( $self->isa('Selenium::Firefox') && $using eq 'name' ) {
        return {
            using => 'css selector',
            value => qq{[name="$query"]}
        };
    }
    else {
        return {
            using => $using,
            value => $query
        };
    }
}

sub _build_using {
    my ( $self, $method ) = @_;

    if ($method) {
        if ( $self->FINDERS->{$method} ) {
            return $self->FINDERS->{$method};
        }
        else {
            die 'Bad method, expected: '
              . join( ', ', keys %{ $self->FINDERS } )
              . ", got $method";
        }
    }
    else {
        return $self->default_finder;
    }
}

sub get_active_element {
    my ($self) = @_;
    my $res = { 'command' => 'getActiveElement' };
    my $ret_data = eval { $self->_execute_command($res) };
    if ($@) {
        die $@;
    }
    else {
        return $self->webelement_class->new(
            id     => $ret_data,
            driver => $self
        );
    }
}

=head2 cache_status

 Description:
    Get the status of the html5 application cache.

 Usage:
    print $driver->cache_status;

 Output:
    <number> - Status code for application cache: {UNCACHED = 0, IDLE = 1, CHECKING = 2, DOWNLOADING = 3, UPDATE_READY = 4, OBSOLETE = 5}

=cut

sub cache_status {
    my ($self) = @_;
    my $res = { 'command' => 'cacheStatus' };
    return $self->_execute_command($res);
}

=head2 set_geolocation

 Description:
    Set the current geographic location - note that your driver must
    implement this endpoint, or else it will crash your session. At the
    very least, it works in v2.12 of Chromedriver.

 Input:
    Required:
        HASH: A hash with key C<location> whose value is a Location hashref. See
        usage section for example.

 Usage:
    $driver->set_geolocation( location => {
        latitude  => 40.714353,
        longitude => -74.005973,
        altitude  => 0.056747
    });

 Output:
    BOOLEAN - success or failure

=cut

sub set_geolocation {
    my ( $self, %params ) = @_;
    my $res = { 'command' => 'setGeolocation' };
    return $self->_execute_command( $res, \%params );
}

=head2 get_geolocation

 Description:
    Get the current geographic location. Note that your webdriver must
    implement this endpoint - otherwise, it will crash your session. At
    the time of release, we couldn't get this to work on the desktop
    FirefoxDriver or desktop Chromedriver.

 Usage:
    print $driver->get_geolocation;

 Output:
    { latitude: number, longitude: number, altitude: number } - The current geo location.

=cut

sub get_geolocation {
    my ($self) = @_;
    my $res = { 'command' => 'getGeolocation' };
    return $self->_execute_command($res);
}

=head2 get_log

 Description:
    Get the log for a given log type. Log buffer is reset after each request.

 Input:
    Required:
        <STRING> - Type of log to retrieve:
        {client|driver|browser|server}. There may be others available; see
        get_log_types for a full list for your driver.

 Usage:
    $driver->get_log( $log_type );

 Output:
    <ARRAY|ARRAYREF> - An array of log entries since the most recent request.

=cut

sub get_log {
    my ( $self, $type ) = @_;
    my $res = { 'command' => 'getLog' };
    return $self->_execute_command( $res, { type => $type } );
}

=head2 get_log_types

 Description:
    Get available log types. By default, every driver should have client,
    driver, browser, and server types, but there may be more available,
    depending on your driver.

 Usage:
    my @types = $driver->get_log_types;
    $driver->get_log($types[0]);

 Output:
    <ARRAYREF> - The list of log types.

=cut

sub get_log_types {
    my ($self) = @_;
    my $res = { 'command' => 'getLogTypes' };
    return $self->_execute_command($res);
}

=head2 set_orientation

 Description:
    Set the browser orientation.

 Input:
    Required:
        <STRING> - Orientation {LANDSCAPE|PORTRAIT}

 Usage:
    $driver->set_orientation( $orientation  );

 Output:
    BOOLEAN - success or failure

=cut

sub set_orientation {
    my ( $self, $orientation ) = @_;
    my $res = { 'command' => 'setOrientation' };
    return $self->_execute_command( $res, { orientation => $orientation } );
}

=head2 get_orientation

 Description:
    Get the current browser orientation. Returns either LANDSCAPE|PORTRAIT.

 Usage:
    print $driver->get_orientation;

 Output:
    <STRING> - your orientation.

=cut

sub get_orientation {
    my ($self) = @_;
    my $res = { 'command' => 'getOrientation' };
    return $self->_execute_command($res);
}

=head2 send_modifier

 Description:
    Send an event to the active element to depress or release a modifier key.

 Input: 2
    Required:
      value - String - The modifier key event to be sent. This key must be one 'Ctrl','Shift','Alt',' or 'Command'/'Meta' as defined by the send keys command
      isdown - Boolean/String - Whether to generate a key down or key up

 Usage:
    $driver->send_modifier('Alt','down');
    $elem->send_keys('c');
    $driver->send_modifier('Alt','up');

    or

    $driver->send_modifier('Alt',1);
    $elem->send_keys('c');
    $driver->send_modifier('Alt',0);

=cut

sub send_modifier {
    my ( $self, $modifier, $isdown ) = @_;
    if ( $isdown =~ /(down|up)/ ) {
        $isdown = $isdown =~ /down/ ? 1 : 0;
    }

    if ( $self->{is_wd3}
        && !( grep { $self->browser_name eq $_ } qw{MicrosoftEdge} ) )
    {
        my $acts = [
            {
                type => $isdown ? 'keyDown' : 'keyUp',
                value => KEYS->{ lc($modifier) },
            },
        ];

        my $action = {
            actions => [
                {
                    id      => 'key',
                    type    => 'key',
                    actions => $acts,
                }
            ]
        };
        _queue_action(%$action);
        return 1;
    }

    my $res = { 'command' => 'sendModifier' };
    my $params = {
        value  => $modifier,
        isdown => $isdown
    };
    return $self->_execute_command( $res, $params );
}

=head2 compare_elements

 Description:
    Test if two element IDs refer to the same DOM element.

 Input: 2
    Required:
        Selenium::Remote::WebElement - WebElement Object
        Selenium::Remote::WebElement - WebElement Object

 Output:
    BOOLEAN

 Usage:
    $driver->compare_elements($elem_obj1, $elem_obj2);

=cut

sub compare_elements {
    my ( $self, $elem1, $elem2 ) = @_;
    my $res = {
        'command' => 'elementEquals',
        'id'      => $elem1->{id},
        'other'   => $elem2->{id}
    };
    return $self->_execute_command($res);
}

=head2 click

 Description:
    Click any mouse button (at the coordinates set by the last move_to command).

 Input:
    button - any one of 'LEFT'/0 'MIDDLE'/1 'RIGHT'/2
             defaults to 'LEFT'
    queue - (optional) queue the click, rather than executing it.  WD3 only.

 Usage:
    $driver->click('LEFT');
    $driver->click(1); #MIDDLE
    $driver->click('RIGHT');
    $driver->click;  #Defaults to left

=cut

sub click {
    my ( $self, $button, $append ) = @_;
    $button = _get_button($button);

    my $res    = { 'command' => 'click' };
    my $params = { 'button'  => $button };

    if ( $self->{is_wd3}
        && !( grep { $self->browser_name eq $_ } qw{MicrosoftEdge} ) )
    {
        $params = {
            actions => [
                {
                    type       => "pointer",
                    id         => 'mouse',
                    parameters => { "pointerType" => "mouse" },
                    actions    => [
                        {
                            type     => "pointerDown",
                            duration => 0,
                            button   => $button,
                        },
                        {
                            type     => "pointerUp",
                            duration => 0,
                            button   => $button,
                        },
                    ],
                }
            ],
        };
        if ($append) {
            _queue_action(%$params);
            return 1;
        }
        return $self->general_action(%$params);
    }

    return $self->_execute_command( $res, $params );
}

sub _get_button {
    my $button = shift;
    my $button_enum = { LEFT => 0, MIDDLE => 1, RIGHT => 2 };
    if ( defined $button && $button =~ /(LEFT|MIDDLE|RIGHT)/i ) {
        return $button_enum->{ uc $1 };
    }
    if ( defined $button && $button =~ /(0|1|2)/ ) {
        #Handle user error sending in "1"
        return int($1);
    }
    return 0;
}

=head2 double_click

 Description:
    Double-clicks at the current mouse coordinates (set by move_to).

 Compatibility:
    On webdriver3 enabled servers, you can double click arbitrary mouse buttons.

 Usage:
    $driver->double_click(button);

=cut

sub double_click {
    my ( $self, $button ) = @_;

    $button = _get_button($button);

    if ( $self->{is_wd3}
        && !( grep { $self->browser_name eq $_ } qw{MicrosoftEdge} ) )
    {
        $self->click( $button, 1 );
        $self->click( $button, 1 );
        return $self->general_action();
    }

    my $res = { 'command' => 'doubleClick' };
    return $self->_execute_command($res);
}

=head2 button_down

 Description:
    Click and hold the left mouse button (at the coordinates set by the
    last move_to command). Note that the next mouse-related command that
    should follow is buttonup . Any other mouse command (such as click
    or another call to buttondown) will yield undefined behaviour.

 Compatibility:
    On WebDriver 3 enabled servers, all this does is queue a button down action.
    You will either have to call general_action() to perform the queue, or an action like click() which also clears the queue.

 Usage:
    $self->button_down;

=cut

sub button_down {
    my ($self) = @_;

    if ( $self->{is_wd3}
        && !( grep { $self->browser_name eq $_ } qw{MicrosoftEdge} ) )
    {
        my $params = {
            actions => [
                {
                    type       => "pointer",
                    id         => 'mouse',
                    parameters => { "pointerType" => "mouse" },
                    actions    => [
                        {
                            type     => "pointerDown",
                            duration => 0,
                            button   => 0,
                        },
                    ],
                }
            ],
        };
        _queue_action(%$params);
        return 1;
    }

    my $res = { 'command' => 'buttonDown' };
    return $self->_execute_command($res);
}

=head2 button_up

 Description:
    Releases the mouse button previously held (where the mouse is
    currently at). Must be called once for every buttondown command
    issued. See the note in click and buttondown about implications of
    out-of-order commands.

 Compatibility:
    On WebDriver 3 enabled servers, all this does is queue a button down action.
    You will either have to call general_action() to perform the queue, or an action like click() which also clears the queue.

 Usage:
    $self->button_up;

=cut

sub button_up {
    my ($self) = @_;

    if ( $self->{is_wd3}
        && !( grep { $self->browser_name eq $_ } qw{MicrosoftEdge} ) )
    {
        my $params = {
            actions => [
                {
                    type       => "pointer",
                    id         => 'mouse',
                    parameters => { "pointerType" => "mouse" },
                    actions    => [
                        {
                            type     => "pointerUp",
                            duration => 0,
                            button   => 0,
                        },
                    ],
                }
            ],
        };
        _queue_action(%$params);
        return 1;
    }

    my $res = { 'command' => 'buttonUp' };
    return $self->_execute_command($res);
}

=head2 upload_file

 Description:
    Upload a file from the local machine to the selenium server
    machine. That file then can be used for testing file upload on web
    forms. Returns the remote-server's path to the file.

    Passing raw data as an argument past the filename will upload
    that rather than the file's contents.

    When passing raw data, be advised that it expects a zipped
    and then base64 encoded version of a single file.
    Multiple files and/or directories are not supported by the remote server.

 Usage:
    my $remote_fname = $driver->upload_file( $fname );
    my $element = $driver->find_element( '//input[@id="file"]' );
    $element->send_keys( $remote_fname );

=cut

# this method duplicates upload() method in the
# org.openqa.selenium.remote.RemoteWebElement java class.

sub upload_file {
    my ( $self, $filename, $raw_content ) = @_;

    my $params;
    if ( defined $raw_content ) {

        #If no processing is passed, send the argument raw
        $params = { file => $raw_content };
    }
    else {
        #Otherwise, zip/base64 it.
        $params = $self->_prepare_file($filename);
    }

    my $res = { 'command' => 'uploadFile' };    # /session/:SessionId/file
    my $ret = $self->_execute_command( $res, $params );

    return $ret;
}

sub _prepare_file {
    my ( $self, $filename ) = @_;

    if ( not -r $filename ) { die "upload_file: no such file: $filename"; }
    my $string = "";                            # buffer
    my $zip    = Archive::Zip->new();
    $zip->addFile( $filename, basename($filename) );
    if ( $zip->writeToFileHandle( IO::String->new($string) ) != AZ_OK ) {
        die 'zip failed';
    }

    return { file => MIME::Base64::encode_base64( $string, '' ) };
}

=head2 get_text

 Description:
    Get the text of a particular element. Wrapper around L</find_element>

 Usage:
    $text = $driver->get_text("//div[\@name='q']");

=cut

sub get_text {
    my $self = shift;
    return $self->find_element(@_)->get_text();
}

=head2 get_body

 Description:
    Get the current text for the whole body. If you want the entire raw HTML instead,
    See L</get_page_source>.

 Usage:
    $body_text = $driver->get_body();

=cut

sub get_body {
    my $self = shift;
    return $self->get_text( '//body', 'xpath' );
}

=head2 get_path

 Description:
     Get the path part of the current browser location.

 Usage:
     $path = $driver->get_path();

=cut

sub get_path {
    my $self     = shift;
    my $location = $self->get_current_url;
    $location =~ s/\?.*//;               # strip of query params
    $location =~ s/#.*//;                # strip of anchors
    $location =~ s#^https?://[^/]+##;    # strip off host
    return $location;
}

=head2 get_user_agent

 Description:
    Convenience method to get the user agent string, according to the
    browser's value for window.navigator.userAgent.

 Usage:
    $user_agent = $driver->get_user_agent()

=cut

sub get_user_agent {
    my $self = shift;
    return $self->execute_script('return window.navigator.userAgent;');
}

=head2 set_inner_window_size

 Description:
     Set the inner window size by closing the current window and
     reopening the current page in a new window. This can be useful
     when using browsers to mock as mobile devices.

     This sub will be fired automatically if you set the
     C<inner_window_size> hash key option during instantiation.

 Input:
     INT - height of the window
     INT - width of the window

 Output:
     BOOLEAN - Success or failure

 Usage:
     $driver->set_inner_window_size(640, 480)

=cut

sub set_inner_window_size {
    my $self     = shift;
    my $height   = shift;
    my $width    = shift;
    my $location = $self->get_current_url;

    $self->execute_script( 'window.open("' . $location . '", "_blank")' );
    $self->close;
    my @handles = @{ $self->get_window_handles };
    $self->switch_to_window( pop @handles );

    my @resize = (
        'window.innerHeight = ' . $height,
        'window.innerWidth  = ' . $width,
        'return 1'
    );

    return $self->execute_script( join( ';', @resize ) ) ? 1 : 0;
}

=head2 get_local_storage_item

 Description:
     Get the value of a local storage item specified by the given key.

 Input: 1
    Required:
        STRING - name of the key to be retrieved

 Output:
     STRING - value of the local storage item

 Usage:
     $driver->get_local_storage_item('key')

=cut

sub get_local_storage_item {
    my ( $self, $key ) = @_;
    my $res    = { 'command' => 'getLocalStorageItem' };
    my $params = { 'key'     => $key };
    return $self->_execute_command( $res, $params );
}

=head2 delete_local_storage_item

 Description:
     Get the value of a local storage item specified by the given key.

 Input: 1
    Required
        STRING - name of the key to be deleted

 Usage:
     $driver->delete_local_storage_item('key')

=cut

sub delete_local_storage_item {
    my ( $self, $key ) = @_;
    my $res    = { 'command' => 'deleteLocalStorageItem' };
    my $params = { 'key'     => $key };
    return $self->_execute_command( $res, $params );
}

sub _coerce_timeout_ms {
    my ($ms) = @_;

    if ( defined $ms ) {
        return _coerce_number($ms);
    }
    else {
        die 'Expecting a timeout in ms';
    }
}

sub _coerce_number {
    my ($maybe_number) = @_;

    if ( Scalar::Util::looks_like_number($maybe_number) ) {
        return $maybe_number + 0;
    }
    else {
        die "Expecting a number, not: $maybe_number";
    }
}

1;
