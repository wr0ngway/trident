require_relative '../../test_helper'

class Trident::CLITest < MiniTest::Should::TestCase

  class Handler
    def initialize(options={})
    end
    def start
    end
  end

  setup do
    @project_root = File.expand_path('../../../..', __FILE__)
    @cli = "#{@project_root}/bin/trident"
  end

  context "#help" do

    should "generate readable usage" do
      out = `#{@cli} --help`
      assert $? == 0
      assert out.lines.all? {|l| l.size <= 81 }
    end

  end

  context "#logging" do

    should "keep own logger when preforking" do
      # Make sure cli keeps log when preforked environment replaces GemLogger.basic_logger
      cmd = "#{@cli} --config #{@project_root}/test/fixtures/trident_logging.yml"
      io = IO.popen(cmd, :err=>[:child, :out])
      wait_for(io, /<pool-mypool1> Pool started with 2 workers/)

      Process.kill("TERM", io.pid)
      Process.wait(io.pid)
    end

  end

  context "#project_root" do

    should "use bundler env for root" do
      cli = Trident::CLI.new([])
      assert_equal @project_root, File.dirname(ENV['BUNDLE_GEMFILE'])
      assert_equal @project_root, cli.send(:project_root)
    end

    should "use cwd for root when no bundler" do
      cli = Trident::CLI.new([])
      Bundler.with_clean_env do
        assert_nil ENV['BUNDLE_GEMFILE']
        assert_equal '.', cli.send(:project_root)
      end
    end

  end

  context "#expand_path" do

    should "expand path relative to project_root" do
      cli = Trident::CLI.new([])
      assert_equal "#{@project_root}/bin", cli.send(:expand_path, "bin")
    end

    should "not expand path if absolute" do
      cli = Trident::CLI.new([])
      assert_equal "/bin", cli.send(:expand_path, "/bin")
    end

    should "handle nil path" do
      cli = Trident::CLI.new([])
      assert_nil cli.send(:expand_path, nil)
    end

  end

  context "#load_config" do

    should "load yml from file" do
      data = <<-ENDDATA
        foo: bar
        baz: [1, 2, 3]
      ENDDATA
      IO.expects(:read).with("/foo").returns(data)
      cli = Trident::CLI.new([])
      config = cli.send(:load_config, "/foo")
      assert_equal "bar", config['foo']
      assert_equal [1, 2, 3], config['baz']
    end

    should "expand erb" do
      data = <<-ENDDATA
        foo: <%= 1 +1 %>
      ENDDATA
      IO.expects(:read).with("/foo").returns(data)
      cli = Trident::CLI.new([])
      config = cli.send(:load_config, "/foo")
      assert_equal 2, config['foo']
    end

    should "use nested environments" do
      begin
        class ::Rails; def self.env; "test"; end; end
        data = <<-ENDDATA
          foo: bar
          test:
            foo: baz
        ENDDATA
        IO.expects(:read).with("/foo").returns(data)
        cli = Trident::CLI.new([])
        config = cli.send(:load_config, "/foo")
        assert_equal "baz", config['foo']
      ensure
        Object.send(:remove_const, :Rails)
      end
    end

  end

  context "#create_handlers" do

    should "create handlers from config" do
      cli = Trident::CLI.new([])
      handlers_config = {
        "handler1" => {
            "environment" => "require 'something'",
            "class" => "Trident::CLITest::Handler",
            "options" => {"foo" => "bar"},
            "signals" => {"stop_forcefully" => "TERM", "stop_gracefully" => "TERM"}
        },
        "handler2" => {
            "environment" => "require 'something'",
            "class" => "Trident::CLITest::Handler",
            "options" => {"foo" => "bar"},
            "signals" => {"stop_forcefully" => "TERM", "stop_gracefully" => "TERM"}
        }
      }
      handlers = cli.send(:create_handlers, handlers_config)
      assert_equal 2, handlers.size
      assert_equal 'handler1', handlers['handler1'].name
      assert_equal "require 'something'", handlers['handler1'].environment
      assert_equal 'Trident::CLITest::Handler', handlers['handler1'].worker_class_name
      assert_equal({"stop_forcefully" => "TERM", "stop_gracefully" => "TERM"}, handlers['handler2'].signal_mappings)
      assert_equal({"foo" => "bar"}, handlers['handler1'].options)
      assert_equal 'handler2', handlers['handler2'].name
    end

  end

  context "#create_pools" do

    setup do
      @handlers = {
          "handler1" => Trident::PoolHandler.new("handler1", nil, nil, nil),
          "handler2" => Trident::PoolHandler.new("handler2", nil, nil, nil)
      }
      @pools_config = {
          "pool1" => {
              "size" => 5,
              "options" => {"foo" => "bar"},
              "handler" => "handler1"
          },
          "pool2" => {
              "size" => 3,
              "options" => {"baz" => "bum"},
              "handler" => "handler2"
          }
      }
    end

    should "create handlers from config" do
      cli = Trident::CLI.new([])
      pools = cli.send(:create_pools, @pools_config, @handlers)
      assert_equal 2, pools.size
      assert_equal 'pool1', pools['pool1'].name
      assert_equal 'pool2', pools['pool2'].name

      assert_equal 5, pools['pool1'].size
      assert_equal @handlers['handler1'], pools['pool1'].handler
      assert_equal({"size" => 5, "options" => {"foo" => "bar"}, "handler" => "handler1"}, pools['pool1'].options)
    end

    should "filter pools if given" do
      cli = Trident::CLI.new([])
      pools = cli.send(:create_pools, @pools_config, @handlers, ['pool1'])
      assert_equal 1, pools.size
      assert_equal 'pool1', pools.values.first.name
    end

  end

  context "#execute" do

    setup do
      data = <<-ENDDATA
        application: test
        handlers:
          handler1:
            environment: ""
            class: Worker
            options:
            signals:
              default: TERM
              stop_forcefully: INT
              stop_gracefully: TERM
              reload: HUP
        pools:
          qless:
            size: 5
            handler: handler1
            options:
      ENDDATA
      IO.stubs(:read).with("/foo").returns(data)
    end

    should "fail if no logfile and pidfile when daemonizing" do

      Trident::SignalHandler.expects(:start).never
      Trident::Pool.any_instance.expects(:fork).never
      Trident::CLI.any_instance.expects(:daemonize).never

      ex = assert_raises(Clamp::UsageError) do
        Trident::CLI.new("").run(["--config",
                                    "/foo",
                                    "--daemon"])
      end
      assert_match "--logfile and --pidfile are required", ex.message

      ex = assert_raises(Clamp::UsageError) do
        Trident::CLI.new("").run(["--config",
                                    "/foo",
                                    "--daemon",
                                    "--pidfile",
                                    Tempfile.new('pid').path])
      end
      assert_match "--logfile and --pidfile are required", ex.message

      ex = assert_raises(Clamp::UsageError) do
        Trident::CLI.new("").run(["--config",
                                    "/foo",
                                    "--daemon",
                                    "--logfile",
                                    Tempfile.new('log').path])
      end
      assert_match "--logfile and --pidfile are required", ex.message
    end

    should "run if given logfile and pidfile when daemonizing" do

      Trident::SignalHandler.expects(:start).once
      Trident::SignalHandler.expects(:join).once
      Trident::Pool.any_instance.stubs(:fork)
      Trident::CLI.any_instance.expects(:daemonize).once

      Trident::CLI.new("").run(["--config",
                                  "/foo",
                                  "--daemon",
                                  "--logfile",
                                  Tempfile.new('log').path,
                                  "--pidfile",
                                  Tempfile.new('pid').path])

    end

  end

end
