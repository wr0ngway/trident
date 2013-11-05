require_relative '../../test_helper'

class Trident::PoolHandlerTest < MiniTest::Should::TestCase

  setup do
    PoolHandler.constants(false).each do |c|
      PoolHandler.send(:remove_const, c) if c =~ /^Test/
    end
  end

  context "#load" do

    should "eval the environment" do
      env = <<-EOS
        class TestPoolWorker; def start; end; end
      EOS
      assert_raises(NameError) { PoolHandler.const_get("TestPoolWorker") }
      handler = PoolHandler.new("foo", "TestPoolWorker", env, {})
      handler.load
      assert PoolHandler.const_get("TestPoolWorker")
    end

  end

  context "#worker_class" do

    should "find the worker class" do
      env = <<-EOS
        class TestPoolWorker; def start; end; end
      EOS
      handler = PoolHandler.new("foo", "TestPoolWorker", env, {})
      handler.load
      assert_match "TestPoolWorker", handler.worker_class.name
    end

  end

  context "#start" do

    should "initialize the handler class with options and call start" do
      env = <<-EOS
        class TestPoolWorker; def initialize(o); @o = o; end; def start; @o.merge("x" => "y"); end; end
      EOS
      handler = PoolHandler.new("foo", "TestPoolWorker", env, {}, {"a" => "b", "c" => "d"})
      handler.load
      assert_equal({"a"=>"z", "c"=>"d", "e"=>"f", "x"=>"y"}, handler.start("e" => "f", "a" => "z"))
    end

  end

  context "#signal_for" do

    should "return the signal for a given action" do
      handler = PoolHandler.new("foo", "TestPoolWorker", nil, {"stop_forcefully" => "KILL"})
      assert_equal "KILL", handler.signal_for("stop_forcefully")
    end

    should "use the default signal if present" do
      handler = PoolHandler.new("foo", "TestPoolWorker", nil, {"default" => "INT", "stop_forcefully" => "KILL"})
      assert_equal "INT", handler.signal_for("stop_gracefully")
    end

    should "default the signal to TERM if no default" do
      handler = PoolHandler.new("foo", "TestPoolWorker", nil, {"stop_forcefully" => "KILL"})
      assert_equal "SIGTERM", handler.signal_for("stop_gracefully")
    end

  end

end
