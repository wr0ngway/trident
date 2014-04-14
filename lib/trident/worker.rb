module Trident
  # @param [Integer] pid - pid of the worker process
  # @param [Trident::Pool] pool - pool managing the worker process.
  class Worker < Struct.new(:pid, :pool)
    # attr_reader :pid, :pool

    # # @param [Integer] pid - pid of the worker process
    # # @param [Trident::Pool] pool - pool managing the worker process.
    # def initialize(pid, pool)
    #   @pid = pid
    #   @pool = pool
    # end

    # Crate a pidfile for this worker so that
    # we may track it
    def save
      File.open(path, 'w') do |f|
        f << "#{pid}"
      end
    end

    # Remove the pidfile associated with this
    # worker
    def destroy
      FileUtils.rm path
    end

    # We determine the time that this worker was
    # created from the creation timestamp on its
    # pidfile
    def created_at
      @created_at ||= File.stat(path).ctime
    end

    protected

    # Path to this worker's pid file
    def path
      File.join(pool.orphans_dir, "#{pid}.pid")
    end
  end
end
