require_relative '../../test_helper'

class Trident::UtilsTest < MiniTest::Should::TestCase
  include Trident::Utils
  
  context "#procline" do
    
    should "set the procline of the process" do
      pid = fork do
        procline "foo", "bar"
      end

      process_name = `ps -o command -p #{pid}`.lines.to_a.last.strip
      assert_equal "trident[foo]: bar", process_name
      Process.kill("KILL", pid)
    end
    
  end
  
end
