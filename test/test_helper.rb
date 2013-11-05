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
require 'minitest/should'
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

class MiniTest::Should::TestCase
  ORIGINAL_PROCLINE = $0

  setup do
    $0 = ORIGINAL_PROCLINE
  end
end

# Allow triggering single tests when running from rubymine
# reopen the installed runner so we don't step on runner customizations
class << MiniTest::Unit.runner
  # Rubymine sends --name=/\Atest\: <context> should <should>\./
  # Minitest runs each context as a suite
  # Minitest filters methods by matching against: <suite>#test_0001_<should>
  # Nested contexts are separted by spaces in rubymine, but ::s in minitest
  
  def _run_suites(suites, type)
    if options[:filter]
      if options[:filter] =~ /\/\\Atest\\: (.*) should (.*)\\\.\//
        context_filter = $1
        should_filter = $2
        should_filter.strip!
        should_filter.gsub!(" ", "_")
        should_filter.gsub!(/\W/, "")
        context_filter = context_filter.gsub(" ", "((::)| )")
        options[:filter] = "/\\A#{context_filter}(Test)?#test(_\\d+)?_should_#{should_filter}\\Z/"
      end
    end
    
    super
  end
  
  # Prevent "Empty test suite" verbosity when running in rubymine
  def _run_suite(suite, type)
    
    filter = options[:filter] || '/./'
    filter = Regexp.new $1 if filter =~ /\/(.*)\//    
    all_test_methods = suite.send "#{type}_methods"
    filtered_test_methods = all_test_methods.find_all { |m|
      filter === m || filter === "#{suite}##{m}"
    }
    
    if filtered_test_methods.size > 0    
      super
    else
      [0, 0]
    end
  end
end
