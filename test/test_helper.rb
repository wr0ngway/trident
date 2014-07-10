require 'rubygems'

#if ENV['CI']
#  require 'coveralls'
#  Coveralls.wear!
#end

require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end

require 'minitest/autorun'
require "minitest/reporters"
require "mocha/setup"
require 'timeout'
require 'tempfile'

reporter = ENV['REPORTER']
reporter = case reporter
  when 'none' then nil
  when 'spec' then MiniTest::Reporters::SpecReporter.new
  when 'progress' then MiniTest::Reporters::ProgressReporter.new
  else MiniTest::Reporters::DefaultReporter.new
end
MiniTest::Reporters.use!(reporter) if reporter

require 'trident'
include Trident

GemLogger.default_logger = Logger.new("/dev/null")

class ForkChild

  attr_reader :pid, :read_from_child

  def initialize
    @read_from_child, @write_from_child = IO.pipe

    @pid = fork do
      @read_from_child.close
      result = yield
      Marshal.dump(result, @write_from_child)
      exit!(0) # skips exit handlers.
    end

    @write_from_child.close
  end

  def wait(time=5)
    timeout(time) do
      result = @read_from_child.read
      begin
        Process.wait(@pid)
      rescue Errno::ECHILD
      end
      raise "child failed" if result.empty?
      Marshal.load(result)
    end
  end

end

class FileCounter

  def initialize(file=Tempfile.new('file_counter').path)
    @file = file
  end

  def increment
    File.open(@file, File::RDWR|File::CREAT, 0644)  do |f|
      f.flock(File::LOCK_EX)
      value = f.read.to_i + 1
      f.rewind
      f.write("#{value}\n")
      f.flush
      f.truncate(f.pos)
    end
  end

  def read
    # read the counter using read lock
    File.open(@file, "r")  do |f|
      f.flock(File::LOCK_SH)
      f.read.to_i
    end
  end

end

def wait_for(io, pattern, interval=5)
  timeout(interval) do
    loop do
      line = io.readline
      puts line if ENV['DEBUG']
      break if line =~ pattern
    end
  end
end

def child_processes(root_pid=Process.pid)
  processes = {}
  relations = {}
  lines = `ps -e -o pid,ppid,command`.lines.to_a
  lines.shift # remove header
  lines.each do |line|
    line.chomp!
    pieces = line.scan(/(\d+)\s+(\d+)\s+(.*)/).first
    pid = pieces[0].to_i
    ppid = pieces[1].to_i
    command = pieces[2].strip

    next if command =~ /^ps/

    processes[pid] = command
    relations[ppid] ||= []
    relations[ppid] << pid
  end

  pids = Array(relations[root_pid])
  pids.each do |pid|
    pids.concat(Array(relations[pid]))
  end

  processes.select {|k, v| pids.include?(k) }
end

def kill_all_child_processes
  child_processes.keys.each {|p| Process.kill("KILL", p) rescue nil }
  Process.waitall
end

module Minitest::Should
  class TestCase < MiniTest::Spec

    # make minitest spec dsl similar to shoulda
    class << self
      alias :setup :before
      alias :teardown :after
      alias :context :describe
      alias :should :it
    end

    ORIGINAL_PROCLINE = $0

    setup do
      $0 = ORIGINAL_PROCLINE
      kill_all_child_processes
    end

    teardown do
      puts "teardown the signal handler or other tests will break: #{self.class} #{self}" if SignalHandler.instance
    end

  end
end

