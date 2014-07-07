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

## Orphaned workers
The ability to track pool processes across a restart - allows a restart to spin up new processes as old ones die off gracefully.

Limitations - It will treat any process that has the same pid from a previous pool as part of
the orphaned processes if the process can be signalled from the pool process. To get around this
you run the pool as a different user, which will prevent the pool from being able to signal the
process.


## TODO

* Add support for reloading the trident config with a HUP signal
* Add support in yml for specifying [process limits](http://www.ruby-doc.org/core-1.9.3/Process.html#method-c-setrlimit) (memory especially)
* Add support for killing off orphans/processes that have been running for an excessively (configurable) long time.

