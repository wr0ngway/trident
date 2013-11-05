module Trident
  class PoolManager
    include GemLogger::LoggerSupport
    include Trident::Utils

    attr_reader :name, :pools, :prefork

    def initialize(name, pools, prefork)
      logger.info "Initializing pool manager"
      procline "manager-#{name}", "(initializing)"
      @name = name
      @pools = pools
      @prefork = prefork
    end

    def start
      logger.info "Starting pools"
      load_handlers if prefork
      pools.each do |pool|
        pool.start
      end
      procline "manager", "managing #{procline_display}"
    end

    def stop_forcefully
      stop('stop_forcefully')
    end

    def stop_gracefully
      stop('stop_gracefully')
    end

    # waits for children to exit
    def wait
      logger.info "Waiting for pools to exit"
      procline "manager", "waiting #{procline_display}"
      pools.each do |pool|
        pool.wait
      end
      :break
    end

    def update
      pools.each do |pool|
        pool.update
      end
      procline "manager", "managing #{procline_display}"
    end

    private

    def procline_display
      display = ""
      pools.each_with_index do |pool, i|
        display << "#{pool.name}#{pool.workers.to_a.inspect}"
        display << " " if i + 1 < pools.size
      end
      display
    end

    def load_handlers
      procline "manager", "preforking #{procline_display}"
      pools.each do |pool|
        pool.handler.load
      end
    end

    # tells all children to stop using action
    def stop(action)
      logger.info "Stopping pools: #{action}"
      procline "manager", "stopping #{procline_display}"
      pools.each do |pool|
        pool.stop(action)
      end
      :break
    end

  end
end