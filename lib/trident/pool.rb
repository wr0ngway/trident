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

    private

    def maintain_worker_count(kill_action)
      cleanup_orphaned_workers
      cleanup_dead_workers(false)

      workers_count = workers.size + orphans.size

      # If the sum of both the workers and orphan workers is under our
      # size requirement let's spawn more workers to reach that size
      if size > workers_count
        spawn_workers(size - workers_count)
      # If we have more workers than the size requirement, let's kill workers off
      # until we hit that size
      elsif size < workers.size
        workers_there_need_to_be = [size - orphans.size, 0].max
        workers_to_kill = workers.size - workers_there_need_to_be

        kill_workers(workers_to_kill, kill_action)
      # If we have more workers and orphan workers than the size requirement, and
      # the workers that push us over are orphans, let's kill off some workers
      elsif size < workers_count
        logger.info "<pool-#{name}> Too many orphans. Killing workers."
        workers_to_kill = [workers_count - size, workers.size].min

        kill_workers(workers_to_kill, kill_action)
      else
        logger.debug "<pool-#{name}> Worker count is correct"
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
