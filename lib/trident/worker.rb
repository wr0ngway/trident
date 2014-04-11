module Trident
  class Worker
    attr_reader :pid, :pool

    def initialize(pid, pool)
      @pid = pid.to_i
      @pool = pool
    end

    # Crate a pidfile for this worker so that
    # we may track it
    def save
      File.open(path, 'w') do |f|
        f << pid.to_s
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

    def to_s
      pid
    end

    protected

    # Path to this worker's pid file
    def path
      File.join(pool.orphans_dir, "#{pid}.pid")
    end
  end
end
