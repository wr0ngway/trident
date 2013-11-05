# Trident

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
