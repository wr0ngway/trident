require 'clamp'
require 'erb'
require 'yaml'
require 'trident/cli_logger'

module Trident
  class CLI < Clamp::Command

    include GemLogger::LoggerSupport
    include Trident::Utils

    def self.description
      "Starts the trident pool manager"
    end

    option "--verbose",
           :flag, "verbose output\n",
           :default => false
    option "--generate-config",
           :flag, "generates an example config file to stdout"
    option "--config",
           "FILENAME", "use the given config file\n",
           :default => "config/trident.yml"
    option "--logfile",
           "FILENAME", "log to the given file"
    option "--pidfile",
           "FILENAME", "store pid in the given pidfile"
    option "--daemon",
           :flag, "run as a daemon",
           :default => false
    option "--pool",
           "POOL", "only run the given pool(s)",
           :multivalued => true


    def execute
      if generate_config?
        puts File.read(File.expand_path("../../../trident.example.yml", __FILE__))
        exit(0)
      end

      procline "cli", "(initializing)"

      self.logfile = expand_path(logfile)
      self.pidfile = expand_path(pidfile)
      self.config = expand_path(config)

      Trident::CLILogger.trident_logger = Logger.new(logfile ? logfile : STDOUT)
      Trident::CLILogger.trident_logger.level = verbose? ? Logger::DEBUG : Logger::INFO
      $stdout.sync = $stderr.sync = true

      if daemon? && (logfile.nil? || pidfile.nil?)
        signal_usage_error "--logfile and --pidfile are required when running as a daemon"
      end

      logger.info "Loading config from: #{config}"
      config_hash = load_config(config)

      if GC.respond_to?(:copy_on_write_friendly=)
        GC.copy_on_write_friendly = true
      end

      daemonize(logfile) if daemon?
      File.write(pidfile, Process.pid.to_s) if pidfile

      handlers = create_handlers(config_hash['handlers'])
      pools = create_pools(config_hash['pools'], handlers, pool_list)

      manager = Trident::PoolManager.new(config_hash['application'],
                                           pools.values,
                                           config_hash['prefork'] == true)
      Trident::SignalHandler.start(config_hash['signals'], manager)
      Trident::SignalHandler.join
    end

    private

    def project_root
      @root ||= ENV['BUNDLE_GEMFILE'] ? "#{File.dirname(ENV['BUNDLE_GEMFILE'])}" : "."
    end

    def expand_path(path)
      if path && path !~ /^\//
        File.expand_path("#{project_root}/#{path}")
      else
        path
      end
    end

    # Configure through yaml file
    def load_config(path_to_yaml_file)
      erb = ERB.new(IO.read(path_to_yaml_file))
      erb.filename = path_to_yaml_file
      config = YAML::load(erb.result)
      config = config[Rails.env.to_s] if defined?(::Rails) && config.has_key?(Rails.env.to_s)
      config
    end

    def daemonize(logfile)
      Process.daemon
      $stdout.reopen(logfile, "a")
      $stderr.reopen(logfile, "a")
    end

    def create_handlers(handlers_config_hash)
      handlers = {}
      handlers_config_hash.each do |name, handler_config|
        handler = Trident::PoolHandler.new(name,
                                             handler_config['class'],
                                             handler_config['environment'],
                                             handler_config['signals'],
                                             handler_config['options'])
        handlers[name] = handler
      end
      handlers
    end

    def create_pools(pools_config_hash, handlers, pool_filter=[])
      pools = {}
      pools_config_hash.each do |name, pool_config|
        handler = handlers[pool_config['handler']]
        raise "No handler defined: #{pool_config['handler']}" unless handler

        next if pool_filter.size > 0 && ! pool_filter.include?(name)

        pool = Trident::Pool.new(name, handler, pool_config)
        pools[name] = pool
      end
      pools
    end
  end
end
