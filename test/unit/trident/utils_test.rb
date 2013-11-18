require_relative '../../test_helper'

class Trident::UtilsTest < MiniTest::Should::TestCase
  include Trident::Utils
  
  context "#procline" do
    
    should "set the procline of the process" do
      pid = fork do
        procline "foo", "bar"
        sleep 1
      end
      process_name = child_processes[pid]
      assert_equal "trident[foo]: bar", process_name
      Process.kill("KILL", pid)
      Process.waitall
    end
    
  end
  
end
