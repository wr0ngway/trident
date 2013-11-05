module Trident
  class SignalHandler
    include GemLogger::LoggerSupport

    CHUNK_SIZE = (16 * 1024)
    SIGNAL_QUEUE_MAX_SIZE = 5
    MSG_STOP = 'STOP'

    class << self

      attr_accessor :instance

      def start(signal_mappings, target)
        raise "Already started, call stop if restart needed" if instance
        logger.info "Starting signal handler"
        self.instance = new(signal_mappings, target)
        instance.start
      end

      def stop
        raise "No signal handler started" unless instance
        logger.info "Stopping signal handler"
        instance.stop
        self.instance = nil
      end

      def reset_for_fork
        raise "No signal handler started" unless instance
        instance.reset_for_fork
        self.instance = nil
      end

    end

    attr_reader :target, :signal_mappings, :signal_queue, :self_pipe, :original_signal_handlers

    def initialize(signal_mappings, target)
      @target = target
      @signal_queue = []
      @self_pipe = []
      @original_signal_handlers = {}
      self.signal_mappings = signal_mappings
    end

    def start
      setup_self_pipe
      setup_signal_handlers

      logger.info "Main loop started"
      loop do
        signal_result = handle_signal_queue
        break if signal_result == :break
        msg = snooze if signal_queue.empty?
        logger.debug "Main loop awake"
        break if msg == MSG_STOP
      end
      logger.info "Main loop exited"
    end

    def stop
      reset_signal_handlers
      wakeup(MSG_STOP)
    end

    def reset_for_fork
      @self_pipe = []
      reset_signal_handlers
    end

    def wakeup(msg='.')
      begin
        # mutexes (and thus logging) not allowed within a trap context
        # puts "Waking main loop"
        self_pipe.last.write_nonblock(msg) # wakeup master process from select
      rescue Errno::EAGAIN, Errno::EINTR
        # pipe is full, master should wake up anyways
        retry
      end
    end

    def snooze
      msg = ""
      begin
        logger.info "Snoozing main loop"
        ready = IO.select([self_pipe.first], nil, nil, 1) or return
        ready.first && ready.first.first or return
        loop { msg << self_pipe.first.read_nonblock(CHUNK_SIZE) }
      rescue Errno::EAGAIN, Errno::EINTR
      end
      msg
    end

    private

    def signal_mappings=(mappings)
      @signal_mappings = {}
      mappings.each do |k, v|
        k = "SIG#{k}" unless k =~ /^SIG/i
        k = k.upcase

        raise ArgumentError,
              "Duplicate signal handler: #{k}" if @signal_mappings.has_key?(k)

        @signal_mappings[k] = Array(v)
      end

      # Should always handle CHLD signals as they wakeup/drive the main
      # loop on status changes from child processes
      @signal_mappings = {"SIGCHLD" => ["update"]}.merge(@signal_mappings)
    end

    def setup_self_pipe
      self_pipe.each { |io| io.close rescue nil }
      self_pipe.replace(IO.pipe)
      self_pipe.each { |io| io.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC) }
    end

    def setup_signal_handlers
      logger.info "Installing signal handlers"
      signal_mappings.each do |signal_name, actions|
        raise ArgumentError,
              "Target does not respond to action: #{actions}" unless actions.all? { |a| target.respond_to?(a) }

        logger.info "Adding signal mapping: #{signal_name} -> #{actions.inspect}"
        original_signal_handlers[signal_name] = trap_deferred(signal_name)
      end
    end

    def reset_signal_handlers
      original_signal_handlers.each do |signal_name, original_handler|
        trap(signal_name, original_handler)
      end
      original_signal_handlers.clear
    end

    # defer a signal for later processing in #join (master process)
    def trap_deferred(signal)
      trap(signal) do |signal_number|
        if signal_queue.size < SIGNAL_QUEUE_MAX_SIZE
          # mutexes (and thus logging) not allowed within a trap context
          # puts "Adding signal to queue: #{signal}"
          signal_queue << signal
          wakeup
        else
          $stderr.puts "Signal queue exceeded max size, ignoring #{signal}"
        end
      end
    end

    def handle_signal_queue
      signal_result = nil
      signal = signal_queue.shift
      if signal
        logger.info "Handling signal: #{signal}"
        actions = signal_mappings[signal]
        if actions
          actions.each do |action|
            logger.info "Sending to target: #{action}"
            signal_result = target.send(action)
          end
        end
      end
      signal_result
    end

  end
end