# selenium-client-perl

WC3 Standard selenium client

Automatically spins up/down drivers when pointing at localhost and nothing is already listening on the provided port

Working Drivers:

* Gecko
* Chrome
* MicrosoftEdge
* Safari

Also can auto-fetch the SeleniumHQ JAR file and run it.
This feature is only tested with the Selenium 4.0 or better JARs.

Also contains:

- Selenium::Specification

Module to turn the Online specification documents for Selenium into JSON specifications for use by API clients

Soon to come:

- Selenium::Server

Pure perl selenium server (that proxies commands to browser drivers, much like the SeleniumHQ Jar)

- Selenium::Grid

Pure perl selenium grid API server

- Selenium::Client::SRD

Drop-in replacement for Selenium::Remote::Driver
