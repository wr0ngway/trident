module Trident
  class PoolHandler

    attr_reader :name, :worker_class_name, :environment, :signal_mappings, :options

    def initialize(name, worker_class_name, environment, signal_mappings, options={})
      @name = name
      @worker_class_name = worker_class_name
      @environment = environment
      @signal_mappings = signal_mappings
      @options = options || {}
    end

    def load
      eval environment if environment
    end

    def worker_class
      self.class.const_get(worker_class_name)
    end

    def start(opts={})
      worker_class.new(self.options.merge(opts)).start
    end

    def signal_for(action)
      signal_mappings[action] || signal_mappings['default'] || "SIGTERM"
    end
  end
end
