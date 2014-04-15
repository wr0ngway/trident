module Trident
  class Pool
    include GemLogger::LoggerSupport
    include Trident::Utils

    attr_reader :name, :handler, :size, :options, :workers, :orphans, :orphans_dir

    def initialize(name, handler, options={})
      @name = name
      @handler = handler
      @size = options.delete('size') || 2
      @options = options || {}
      @workers = Set.new
      @orphans_dir = options.delete('pids_dir') || File.join(Dir.pwd, 'trident-pools', name, 'pids')
      @orphans = load_orphans(orphans_dir)
    end

    def load_orphans(path_to_orphans_dir)
      unless File.exists?(path_to_orphans_dir)
        FileUtils.mkdir_p(path_to_orphans_dir)
      end

      orphans = Set.new

      Dir.foreach(path_to_orphans_dir) do |file|
        path = File.join(path_to_orphans_dir, file)
        next if File.directory?(path)

        pid = Integer(IO.read(path))
        orphan_worker = Worker.new(pid, self)
        orphans << orphan_worker
      end

      orphans
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

    # @return [Boolean] true iff total_workers_count > size.
    # false otherwise
    def above_threshold?
      size < total_workers_count
    end

    # @return [Boolean] true iff total_workers_count == size.
    # false otherwise
    def at_threshold?
      size == total_workers_count
    end

    # @return [Boolean] true iff workers.size > 0.
    # false otherwise
    def has_workers?
      workers.size > 0
    end

    # @return [Integer] total number of workers including orphaned
    # workers.
    def total_workers_count
      workers.size + orphans.size
    end

    private

    def maintain_worker_count(kill_action)
      cleanup_orphaned_workers
      cleanup_dead_workers(false)

      if at_threshold?
        logger.debug "<pool-#{name}> Worker count is correct."
      # If we are above the threshold and we have workers
      # then reduce the number of workers.
      elsif above_threshold? && has_workers?
        overthreshold = total_workers_count - size
        workers_to_kill = [overthreshold, workers.size].min

        logger.info("<pool-#{name}> Total workers #{workers.size} above threshold #{size} killing #{workers_to_kill}.")
        kill_workers(workers_to_kill, kill_action)
      # If we are above the threshold, and no workers
      # then we can't do anything, but lets log out a
      # message indicating this state.
      elsif above_threshold?
        logger.info("<pool-#{name}> Waiting on orphans before spawning workers.")
      # If the sum of both the workers and orphan workers is under our
      # size requirement let's spawn the number of workers required to
      # reach that size.
      else
        logger.info("<pool-#{name}> Orphans #{orphans.size}, Workers #{workers.size}")
        spawn_workers(size - total_workers_count)
      end
    end

    # Remove orphan workers which are either not running
    # or which we don't have permission to signal (thereby telling us they
    # where never a part of the pool)
    def cleanup_orphaned_workers
      orphans.clone.each do |worker|
        begin
          # Check if the process is running
          Process.kill(0, worker.pid)
        rescue Errno::EPERM, Errno::ESRCH => e
          # If we get EPERM (Permission error) or ESRCH (No process with that pid)
          # stop tracking that worker
          logger.info("<pool-#{name}> Cleaning up orphaned worker #{worker.pid} because #{e.class.name}:#{e.message})")
          orphans.delete(worker)
          worker.destroy
        rescue => e
          # Make sure we catch any unexpected errors when signaling the process.
          logger.error("<pool-#{name}> failed cleaning up worker #{worker.pid} because #{e.class.name}:#{e.message})")
        end
      end
    end

    def cleanup_dead_workers(blocking=true)
      wait_flags = blocking ? 0 : Process::WNOHANG
      workers.clone.each do |worker|
        begin
          if Process.wait(worker.pid, wait_flags)
            workers.delete(worker)
            worker.destroy
          end
        rescue Errno::EINTR
          logger.warn("<pool-#{name}> Interrupted cleaning up workers, retrying")
          retry
        rescue Errno::ECHILD
          logger.warn("<pool-#{name}> Error cleaning up workers, ignoring")
          # Calling Process.wait on a pid that was already waited on throws
          # a ECHILD, so may as well remove it from our list of workers
          workers.delete(worker)
          worker.destroy
        end
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
      workers.to_a[-count, count].each do |worker|
        kill_worker(worker, action)
      end
    end

    def spawn_worker
      pid = fork do
        procline "pool-#{name}-worker", "starting handler #{handler.name}"
        Trident::SignalHandler.reset_for_fork
        handler.load
        handler.start(options)
      end

      worker = Worker.new(pid, self)
      worker.save

      workers << worker
      logger.info "<pool-#{name}> Spawned worker #{pid}, worker count now at #{workers.size}"
    end

    def kill_worker(worker, action)
      sig = handler.signal_for(action)
      raise "<pool-#{name}> No signal for action: #{action}" unless sig
      logger.info "<pool-#{name}> Sending signal to worker: #{worker.pid}/#{sig}/#{action}"
      Process.kill(sig, worker.pid)
      workers.delete(worker)
      worker.destroy
      logger.info "<pool-#{name}> Killed worker #{worker.pid}, worker count now at #{workers.size}"
    end
  end
end
