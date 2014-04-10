module Trident
  class Worker
    attr_reader :pid, :pool

    def initialize(pid, pool)
      @pid = pid.to_i
      @pool = pool
    end

    def save
      File.open(path, 'w') do |f|
        f << pid.to_s
      end
    end

    def destroy
      FileUtils.rm path 
    end

    def created_at
      @created_at ||= File.stat(path).ctime
    end

    protected

    def path
      File.join(pool.orphans_dir, "#{pid}.pid")
    end
  end
end
