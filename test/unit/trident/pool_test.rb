require_relative '../../test_helper'
require 'pry'

class Trident::PoolTest < MiniTest::Should::TestCase
  class DeadbeatPool < Pool
    def stop
      @size = 0
    end
  end

  setup do
    SignalHandler.stubs(:reset_for_fork)

    PoolHandler.constants(false).each do |c|
      PoolHandler.send(:remove_const, c) if c =~ /^Test/
    end
    env = <<-EOS
      class TestPoolWorker
        def initialize(o)
          @o = o
        end
        def start
          sleep(@o['sleep']) if @o['sleep']
        end
      end
    EOS
    signal_mappings = {'stop_forcefully' => 'KILL', 'stop_gracefully' => 'TERM'}
    @handler = PoolHandler.new("foo", "TestPoolWorker", env, signal_mappings, {})
  end

  context "#spawn_worker" do
    should "fork a worker" do
      pool = Pool.new("foo", @handler, 'size' => 1, 'pids_dir' => Dir.mktmpdir, 'sleep' => 0.1)
      assert_empty pool.workers
      pool.send(:spawn_worker)
      assert_equal 1, pool.workers.size
      Process.waitpid(pool.workers.first.pid)
      assert $?.success?
    end
  end

  context "#kill_worker" do
    should "kill a worker" do
      pool = Pool.new("foo", @handler, 'size' => 1, 'pids_dir' => Dir.mktmpdir, 'sleep' => 1)
      pool.send(:spawn_worker)
      worker = pool.workers.first

      pool.send(:kill_worker, worker, 'stop_forcefully')
      Process.waitpid(worker.pid)
      assert ! $?.success?
      assert_empty pool.workers
    end

    should "kill a worker with specific signal" do
      pool = Pool.new("foo", @handler, 'size' => 1, 'pids_dir' => Dir.mktmpdir, 'sleep' => 1)
      pool.send(:spawn_worker)
      worker = pool.workers.first

      Process.expects(:kill).with("TERM", worker.pid)
      pool.send(:kill_worker, worker, 'stop_gracefully')
    end
  end

  context "#spawn_workers" do
    should "start multiple workers" do
      pool = Pool.new("foo", @handler, 'size' => 4, 'pids_dir' => Dir.mktmpdir, 'sleep' => 1)
      pool.send(:spawn_workers, 4)
      assert_equal 4, pool.workers.size
    end
  end

  context "#kill_workers" do
    should "kill multiple workers, most recent first" do
      pool = Pool.new("foo", @handler, 'size' => 4, 'pids_dir' => Dir.mktmpdir, 'sleep' => 1)
      pool.send(:spawn_workers, 4)
      orig_workers = pool.workers.dup
      assert_equal 4, orig_workers.size

      pool.send(:kill_workers, 3, 'stop_forcefully')
      assert_equal 1, pool.workers.size
      assert_equal orig_workers.first, pool.workers.first
    end
  end

  context "#cleanup_dead_workers" do
    should "stop tracking workers that have died" do
      pool = Pool.new("foo", @handler, 'size' => 4, 'pids_dir' => Dir.mktmpdir, 'sleep' => 0)
      pool.send(:spawn_workers, 4)

      sleep 0.1
      assert_equal 4, pool.workers.size
      pool.send(:cleanup_dead_workers)
      assert_equal 0, pool.workers.size
    end

    should "block waiting for workers that have died when blocking" do
      pool = Pool.new("foo", @handler, 'size' => 1, 'pids_dir' => Dir.mktmpdir, 'sleep' => 0.2)
      pool.send(:spawn_workers, 1)
      assert_equal 1, pool.workers.size

      thread = Thread.new { pool.send(:cleanup_dead_workers, true) }
      sleep(0.1)
      assert_equal 1, pool.workers.size
      thread.join
      assert_equal 0, pool.workers.size
    end

    should "not block waiting for workers that have died when not-blocking" do
      pool = Pool.new("foo", @handler, 'size' => 1, 'pids_dir' => Dir.mktmpdir, 'sleep' => 0.1)
      pool.send(:spawn_workers, 1)
      assert_equal 1, pool.workers.size

      pool.send(:cleanup_dead_workers, false)
      assert_equal 1, pool.workers.size
    end

    should "cleanup workers that have died even if already waited on" do
      pool = Pool.new("foo", @handler, 'size' => 4, 'pids_dir' => Dir.mktmpdir, 'sleep' => 0)
      pool.send(:spawn_workers, 4)

      # Calling process.wait on a pid that was already waited on throws a ECHLD
      Process.waitall
      assert_equal 4, pool.workers.size
      pool.send(:cleanup_dead_workers, false)

      assert_equal 0, pool.workers.size
    end
  end

  context "#maintain_worker_count" do
    should "spawn workers when count is low" do
      pool = Pool.new("foo", @handler, 'size' => 2, 'pids_dir' => Dir.mktmpdir, 'sleep' => 0.1)
      assert_empty pool.workers

      pool.send(:maintain_worker_count, 'stop_gracefully')
      assert_equal 2, pool.workers.size
    end

    should "kill workers when count is high" do
      pool = Pool.new("foo", @handler, 'size' => 2, 'pids_dir' => Dir.mktmpdir, 'sleep' => 0.1)
      pool.send(:spawn_workers, 4)
      assert_equal 4, pool.workers.size

      pool.send(:maintain_worker_count, 'stop_gracefully')
      assert_equal 2, pool.workers.size
    end

    should "kill workers with given action when count is high" do
      pool = Pool.new("foo", @handler, 'size' => 2, 'pids_dir' => Dir.mktmpdir, 'sleep' => 0.1)
      pool.send(:spawn_workers, 4)
      assert_equal 4, pool.workers.size

      Process.expects(:kill).with("KILL", pool.workers.to_a[-1].pid)
      Process.expects(:kill).with("KILL", pool.workers.to_a[-2].pid)
      pool.send(:maintain_worker_count, 'stop_forcefully')

      pool.send(:spawn_workers, 2)
      Process.expects(:kill).with("TERM", pool.workers.to_a[-1].pid)
      Process.expects(:kill).with("TERM", pool.workers.to_a[-2].pid)
      pool.send(:maintain_worker_count, 'stop_gracefully')
    end

    should "not spawn new workers when orphan count is too high " do
      dir = Dir.mktmpdir
      pool = DeadbeatPool.new("foo", @handler, 'size' => 4, 'pids_dir' => dir, 'sleep' => 0.1)
      pool.start
      pool.stop

      new_pool = Pool.new("foo", @handler, 'size' => 2, 'pids_dir' => dir, 'sleep' => 0.1)
      assert_equal 0, new_pool.workers.size
      assert_equal 4, new_pool.orphans.size
    end

    should "kill workers when orphan count is high and workers are present" do
      dir = Dir.mktmpdir
      pool = DeadbeatPool.new("foo", @handler, 'size' => 4, 'pids_dir' => dir, 'sleep' => 0.1)
      pool.start
      pool.stop

      new_pool = Pool.new("foo", @handler, 'size' => 2, 'pids_dir' => dir, 'sleep' => 0.1)
      assert_equal 4, new_pool.orphans.size

      new_pool.send(:spawn_workers, 4)
      assert_equal 4, pool.workers.size

      pool.send(:maintain_worker_count, 'stop_gracefully')

      pool.workers.each do |worker|
        Process.waitpid(worker.pid)
      end

      assert_equal 0, pool.workers.size
    end

    should "do nothing when count is correct" do
      Process.expects(:kill).never
      pool = Pool.new("foo", @handler, 'size' => 2, 'pids_dir' => Dir.mktmpdir, 'sleep' => 0.1)
      pool.send(:spawn_workers, 2)
      orig_workers = pool.workers.dup
      assert_equal 2, orig_workers.size

      pool.send(:maintain_worker_count, 'stop_gracefully')
      assert_equal 2, pool.workers.size
      assert_equal orig_workers, pool.workers
    end
  end

  context "#start" do
    should "start up the workers" do
      pool = Pool.new("foo", @handler, 'size' => 2, 'pids_dir' => Dir.mktmpdir, 'sleep' => 0.1)
      pool.start
      assert_equal 2, pool.workers.size
    end
  end

  context "#stop" do
    should "stop the workers" do
      pool = Pool.new("foo", @handler, 'size' => 2, 'pids_dir' => Dir.mktmpdir, 'sleep' => 0.1)
      pool.start
      assert_equal 2, pool.workers.size
      pool.stop
      assert_empty pool.workers
    end
  end

  context "#wait" do
    should "block till all workers complete" do
      pool = Pool.new("foo", @handler, 'size' => 2, 'pids_dir' => Dir.mktmpdir, 'sleep' => 0.1)
      pool.start
      assert_equal 2, pool.workers.size
      pool.wait
      assert_empty pool.workers
    end
  end

  context "#update" do
    should "update monitored workers" do
      pool = Pool.new("foo", @handler, 'size' => 2, 'pids_dir' => Dir.mktmpdir, 'sleep' => 0.2)
      pool.start
      orig_workers = pool.workers.dup
      assert_equal 2, orig_workers.size
      Process.kill("KILL", orig_workers.first.pid)
      sleep(0.1)
      assert_equal orig_workers, pool.workers
      pool.update
      refute_equal orig_workers, pool.workers
    end
  end

  context "#load_orphans" do
    should "load orphaned workers from the pool's pid directory" do
      dir = Dir.mktmpdir
      pool = DeadbeatPool.new("foo", @handler, 'size' => 1, 'pids_dir' => dir, 'sleep' => 0.1)
      pool.start
      pid = pool.workers.first.pid
      pool.stop

      new_pool = Pool.new("foo", @handler, 'size' => 1, 'pids_dir' => dir, 'sleep' => 0.1)
      assert_equal 1, new_pool.orphans.size
      assert_equal pid, new_pool.orphans.first.pid
    end

    should "not load dead orphan workers" do
      tmp = Dir.mktmpdir
      File.open(File.join(tmp, "99999.pid"), 'w') do |f|
        f << '99999'
      end

      pool = Pool.new("foo", @handler, 'pids_dir' => tmp , 'size' => 2, 'sleep' => 0.1)
      assert 0, pool.orphans.size
    end
  end

  context "#cleanup_orphaned_workers" do
    should "remove any orphaned workers that can't be controlled" do
      dir = Dir.mktmpdir
      pool = DeadbeatPool.new("foo", @handler, 'size' => 1, 'pids_dir' => dir, 'sleep' => 0.1)
      pool.start
      pid = pool.workers.first.pid
      pool.stop

      new_pool = Pool.new("foo", @handler, 'size' => 1, 'pids_dir' => dir, 'sleep' => 0.1)
      assert_equal 1, new_pool.orphans.size
      assert_equal pid, new_pool.orphans.first.pid
      Process.kill(9, pid)
      Process.waitpid(pid)

      new_pool.send(:cleanup_orphaned_workers)

      assert 0, new_pool.orphans.size
    end
  end
end
