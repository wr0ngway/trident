require_relative '../../test_helper'

class Trident::PoolManagerTest < MiniTest::Should::TestCase

  setup do
    SignalHandler.stubs(:reset_for_fork)

    PoolHandler.constants(false).each do |c|
      PoolHandler.send(:remove_const, c) if c =~ /^Test/
    end

    $counter = FileCounter.new

    env = <<-EOS
      $counter.increment

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
    @handler1 = PoolHandler.new("foo", "TestPoolWorker", env, signal_mappings, {})
    @handler2 = PoolHandler.new("bar", "TestPoolWorker", env, signal_mappings, {})
    @pool1 = Pool.new("foo", @handler1, 2, 'sleep' => 0.1)
    @pool2 = Pool.new("bar", @handler2, 3, 'sleep' => 0.1)
  end

  context "#start" do

    should "start workers for each pool" do
      manager = PoolManager.new("mymanager", [@pool1, @pool2], false)
      manager.expects(:load_handlers).never
      manager.start
      assert_equal 2, @pool1.workers.size
      assert_equal 3, @pool2.workers.size
      Process.waitall
      # once for each worker
      assert_equal 5, $counter.read
    end

    should "preload env for all handlers if prefork" do
      manager = PoolManager.new("mymanager", [@pool1, @pool2], true)
      manager.start
      assert_equal 2, @pool1.workers.size
      assert_equal 3, @pool2.workers.size
      Process.waitall
      # once for each worker plus once for each handler
      assert_equal 7, $counter.read
    end

  end

  context "#stop" do

    should "stop workers for each pool" do
      manager = PoolManager.new("mymanager", [@pool1, @pool2], false)
      manager.start
      assert_equal 2, @pool1.workers.size
      assert_equal 3, @pool2.workers.size

      manager.send(:stop, "stop_forcefully")
      Process.waitall

      assert_empty @pool1.workers
      assert_empty @pool2.workers
    end

    should "send stop_forcefully" do
      manager = PoolManager.new("mymanager", [@pool1, @pool2], false)
      manager.start

      manager.expects(:stop).with("stop_forcefully")
      manager.stop_forcefully
    end

    should "send stop_gracefully" do
      manager = PoolManager.new("mymanager", [@pool1, @pool2], false)
      manager.start

      manager.expects(:stop).with("stop_gracefully")
      manager.stop_gracefully
    end

  end

  context "#wait" do

    should "wait for processes to exit" do
      manager = PoolManager.new("mymanager", [@pool1, @pool2], false)
      manager.start
      assert_equal 2, @pool1.workers.size
      assert_equal 3, @pool2.workers.size

      thread = Thread.new { manager.wait }
      sleep 0.01
      assert_equal 2, @pool1.workers.size
      assert_equal 3, @pool2.workers.size

      thread.join
      assert_empty @pool1.workers
      assert_empty @pool2.workers
    end

  end

  context "#update" do

    should "update status of all pools" do
      manager = PoolManager.new("mymanager", [@pool1, @pool2], false)
      manager.start
      orig_pool1 = @pool1.workers.dup
      orig_pool2 = @pool2.workers.dup

      assert_equal orig_pool1, @pool1.workers
      assert_equal orig_pool2, @pool2.workers
      sleep 0.3

      manager.update
      refute_equal orig_pool1, @pool1.workers
      refute_equal orig_pool2, @pool2.workers
    end

  end

end
