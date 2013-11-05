module Trident
  class Pool
    include GemLogger::LoggerSupport
    include Trident::Utils

    attr_reader :name, :handler, :size, :options, :workers

    def initialize(name, handler, size, options={})
      @name = name
      @handler = handler
      @size = size
      @options = options || {}
      @workers = Set.new
    end

    def start
      logger.info "<pool-#{name}> Starting pool"
      maintain_worker_count('stop_gracefully')
      logger.info "<pool-#{name}> Pool started with #{workers.size} workers"
    end

    def stop(action='stop_gracefully')
      logger.info "<pool-#{name}> Stopping pool"
      @size = 0
      maintain_worker_count(action)
      logger.info "<pool-#{name}> Pool stopped"
    end

    def wait
      logger.info "<pool-#{name}> Waiting for pool"
      cleanup_dead_workers(true)
      logger.info "<pool-#{name}> Wait complete"
    end

    def update
      logger.info "<pool-#{name}> Updating pool"
      maintain_worker_count('stop_gracefully')
      logger.info "<pool-#{name}> Pool up to date"
    end

    private

    def maintain_worker_count(kill_action)
      cleanup_dead_workers(false)

      if size > workers.size
        spawn_workers(size - workers.size)
      elsif size < workers.size
        kill_workers(workers.size - size, kill_action)
      else
        logger.debug "<pool-#{name}> Worker count is correct"
      end
    end

    def cleanup_dead_workers(blocking=true)
      wait_flags = blocking ? 0 : Process::WNOHANG
      workers.clone.each do |pid|
        begin
          wpid = Process.wait(pid, wait_flags)
        rescue Errno::EINTR
          logger.warn("<pool-#{name}> Interrupted cleaning up workers, retrying")
          retry
        rescue Errno::ECHILD
          logger.warn("<pool-#{name}> Error cleaning up workers, ignoring")
          # Calling process.wait on a pid that was already waited on throws
          # a ECHLD, so may as well remove it from our list of workers
          wpid = pid
        end
        workers.delete(wpid) if wpid
      end
    end

    def spawn_workers(count)
      logger.info "<pool-#{name}> Spawning #{count} workers"
      count.times do
        spawn_worker
      end
    end

    def kill_workers(count, action)
      logger.info "<pool-#{name}> Killing #{count} workers with #{action}"
      workers.to_a[-count, count].each do |pid|
        kill_worker(pid, action)
      end
    end

    def spawn_worker
      pid = fork do
        procline "pool-#{name}-worker", "starting handler #{handler.name}"
        Trident::SignalHandler.reset_for_fork
        handler.load
        handler.start(options)
      end
      workers << pid
      logger.info "<pool-#{name}> Spawned worker #{pid}, worker count now at #{workers.size}"
    end

    def kill_worker(pid, action)
      sig = handler.signal_for(action)
      raise "<pool-#{name}> No signal for action: #{action}" unless sig
      logger.info "<pool-#{name}> Sending signal to worker: #{pid}/#{sig}/#{action}"
      Process.kill(sig, pid)
      workers.delete(pid)
      logger.info "<pool-#{name}> Killed worker #{pid}, worker count now at #{workers.size}"
    end

  end
end
