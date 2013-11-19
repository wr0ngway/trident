# Trident

[![Build Status](https://secure.travis-ci.org/wr0ngway/trident.png)](http://travis-ci.org/wr0ngway/trident)
[![Coverage Status](https://coveralls.io/repos/wr0ngway/trident/badge.png?branch=master)](https://coveralls.io/r/wr0ngway/trident?branch=master)

A ruby gem for managing pools of forked workers

## Installation

Add this line to your application's Gemfile:

    gem 'trident'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install trident

## Usage

After installing the gem, use the 'trident' binary to generate an example configuration file:

    trident --generate-config > config/trident.yml

Edit the file with your desired setup, then run trident to launch all your worker pools

See other command line options with

    trident --help


## TODO

* Add support for reloading the trident config with a HUP signal
* Add support in yml for specifying [process limits](http://www.ruby-doc.org/core-1.9.3/Process.html#method-c-setrlimit) (memory especially)
* Add ability to track pool processes across a restart (or maybe only across a HUP) - allows a restart to spin up new processes as old ones die off gracefully.
