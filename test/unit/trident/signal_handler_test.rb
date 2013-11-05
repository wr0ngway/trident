require_relative '../../test_helper'

class Trident::SignalHandlerTest < MiniTest::Should::TestCase

  class Target
    attr_accessor :received

    def initialize
      @received = []
    end

    def method_missing(method, *args, &block)
      @received << [method, args, block]
      method =~ /action_(.*)/ ? $1.to_sym : :noaction
    end

    def respond_to_missing?(name, include_private = false)
      name !~ /nomethod/
    end
  end

  def do_in_child
    read_from_child, write_from_child = IO.pipe

    pid = fork do
      read_from_child.close
      result = yield
      Marshal.dump(result, write_from_child)
      exit!(0) # skips exit handlers.
    end

    [pid, read_from_child]
    write_from_child.close
    result = read_from_child.read
    Process.wait(pid)
    raise "child failed" if result.empty?
    Marshal.load(result)
  end

  context "#initialize" do

    should "add in CHLD handler" do
      handler = SignalHandler.new({}, Target.new)
      assert_equal({"SIGCHLD" => ["update"]}, handler.signal_mappings)
    end

    should "allow CHLD handler replacement" do
      handler = SignalHandler.new({"CHLD" => "foo"}, Target.new)
      assert_equal({"SIGCHLD" => ["foo"]}, handler.signal_mappings)
    end

  end

  context "#signal_mappings==" do

    should "normalize signal names" do
      handler = SignalHandler.new({}, Target.new)
      handler.send :signal_mappings=,
                   {"int" => "foo", "sigterm" => "bar",
                    "USR1" => "baz", "SIGUSR2" => ["bum", "hum"]}

      assert_equal({"SIGCHLD" => ["update"], "SIGINT" => ["foo"],
                    "SIGTERM" => ["bar"], "SIGUSR1" => ["baz"],
                    "SIGUSR2" => ["bum", "hum"]}, handler.signal_mappings)
    end

    should "fail for duplicate signals" do
      handler = SignalHandler.new({}, Target.new)
      signals = {"int" => "foo", "sigint" => "bar"}
      assert_raises(ArgumentError) { handler.send :signal_mappings=, signals }
    end

  end

  context "#setup_self_pipe" do

    should "create new pipes" do
      handler = SignalHandler.new({}, Target.new)
      assert_equal 0, handler.send(:self_pipe).size
      handler.send :setup_self_pipe
      assert_equal 2, handler.send(:self_pipe).size
    end

    should "replace pipes with new ones" do
      handler = SignalHandler.new({}, Target.new)
      handler.send :setup_self_pipe
      old = handler.send(:self_pipe).dup
      assert_equal 2, old.size
      handler.send :setup_self_pipe
      new = handler.send(:self_pipe).dup
      assert_equal 2, new.size
      refute_equal old, new
    end

  end

  context "#setup_signal_handlers" do

    should "trap given signals" do
      signals = {"int" => "foo", "term" => "bar"}
      handler = SignalHandler.new(signals, Target.new)

      handler.expects(:trap_deferred).with("SIGINT")
      handler.expects(:trap_deferred).with("SIGTERM")
      handler.expects(:trap_deferred).with("SIGCHLD")
      handler.send(:setup_signal_handlers)
    end

    should "save original signals" do
      signals = {"int" => "foo", "term" => "bar"}
      handler = SignalHandler.new(signals, Target.new)

      handler.stubs(:trap_deferred)
      handler.send(:setup_signal_handlers)
      assert_equal({"SIGCHLD" => nil, "SIGINT" => nil, "SIGTERM" => nil},
                   handler.original_signal_handlers)
    end

    should "fail for unhandled methods" do
      signals = {"term" => "nomethod"}
      handler = SignalHandler.new(signals, Target.new)

      handler.stubs(:trap_deferred)
      assert_raises(ArgumentError) { handler.send(:setup_signal_handlers) }
    end

  end

  context "#reset_signal_handlers" do

    should "reset signals" do
      signals = {"int" => "foo", "term" => "bar"}
      handler = SignalHandler.new(signals, Target.new)

      handler.stubs(:trap_deferred)
      handler.send(:setup_signal_handlers)

      handler.expects(:trap).with("SIGINT", nil)
      handler.expects(:trap).with("SIGTERM", nil)
      handler.expects(:trap).with("SIGCHLD", nil)
      handler.send(:reset_signal_handlers)
      assert_empty handler.original_signal_handlers
    end

  end

  context "#handle_signal_queue" do

    setup do
      signals = {"int" => "foo", "term" => "bar"}
      @target = Target.new
      @handler = SignalHandler.new(signals, @target)
    end

    should "do nothing when queue empty" do
      assert_empty @handler.signal_queue
      assert_nil @handler.send(:handle_signal_queue)
      assert_empty @target.received
    end

    should "do nothing if signal unknown" do
      @handler.signal_queue << "SIGUSR1"
      assert_nil @handler.send(:handle_signal_queue)
      assert_empty @target.received
    end

    should "call target for known signal" do
      @handler.signal_queue << "SIGINT"
      assert_equal :noaction, @handler.send(:handle_signal_queue)
      assert_equal [[:foo, [], nil]], @target.received
    end

  end

  context "#snooze/wakeup" do

    should "block until woken" do
      handler = SignalHandler.new({}, Target.new)
      handler.send(:setup_self_pipe)
      thread = Thread.new { handler.snooze }
      sleep 0.1
      assert thread.alive?
      handler.wakeup
      sleep 0.1
      refute thread.alive?
      assert_equal ".", thread.value
    end

  end

  context "#start/stop" do

    should "block until woken" do
      handler = SignalHandler.new({}, Target.new)
      handler.stubs(:trap)
      thread = Thread.new { handler.start }
      sleep 0.1
      assert thread.alive?
      handler.stop
      sleep 0.1
      refute thread.alive?
    end

  end

  context ".start" do

    should "fail if already instantiated" do
      SignalHandler.instance = SignalHandler.new({}, Target.new)
      assert_raises(RuntimeError) { SignalHandler.start({}, Target.new) }
    end

  end

  context ".stop" do

    should "fail if not instantiated" do
      SignalHandler.instance = nil
      assert_raises(RuntimeError) { SignalHandler.stop }
    end

  end

  context "api" do

    should "react to signals" do
      fc = ForkChild.new do
        target = Target.new
        SignalHandler.start({"int" => "foo", "term" => "bar", "usr1" => "action_break"}, target)
        target.received
      end

      sleep 0.1
      Process.kill("TERM", fc.pid)
      sleep 0.1
      Process.kill("INT", fc.pid)
      sleep 0.1
      Process.kill("USR1", fc.pid)

      received = fc.wait
      assert_equal [[:bar, [], nil], [:foo, [], nil], [:action_break, [], nil]], received
    end

    should "honor signal queue limit" do
      fc = ForkChild.new do
        $stderr.reopen("/dev/null")
        target = Target.new
        SignalHandler.start({"int" => "foo", "term" => "bar", "usr1" => "action_break"}, target)
        target.received
      end
      sleep 0.1

      50.times { Process.kill("TERM", fc.pid) }
      sleep 0.2
      Process.kill("USR1", fc.pid)
      received = fc.wait
      assert received.size > 0
      assert received.size < 50
    end

  end
end
