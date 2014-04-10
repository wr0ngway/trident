require_relative '../test_helper'

class Trident::TridentTest < MiniTest::Should::TestCase
  setup do
    @project_root = File.expand_path('../../fixtures/integration_project', __FILE__)
    @cli = "#{File.expand_path('../../..', __FILE__)}/bin/trident"
  end


  def parse_manager(manager_str)
    pools = {}

    pool = manager_str.scan(/managing (\w+)\[/).flatten.first
    pids = manager_str.scan(/@pid=(\d+)/).flatten.map(&:to_i).uniq

    pools[pool] = pids
    pools
  end

  context "basic usage" do
    should "start and stop pools" do
      cmd = "#{@cli} --verbose --config #{@project_root}/config/trident.yml"
      io = IO.popen(cmd, :err=>[:child, :out])

      wait_for(io, /<pool-mypool1> Pool started with 3 workers/)
      wait_for(io, /<pool-mypool2> Pool started with 2 workers/)

      processes = child_processes
      assert_equal 6, processes.size
      manager = processes[io.pid]
      pools = parse_manager(manager)
      pools.each do |pool, pids|
        pids.each do |pid|
          assert processes[pid], "no worker process"
          assert_match /trident[pool-#{pool}-worker]/, processes[pid], "worker process not in right pool"
        end
      end

      Process.kill("USR1", io.pid)

      wait_for(io, /<pool-mypool1> Pool stopped/)
      wait_for(io, /<pool-mypool2> Pool stopped/)
      wait_for(io, /Main loop exited/)

      Process.wait(io.pid)
      assert_empty child_processes
    end
  end

  context "worker maintenance" do
    should "restart failed workers" do
      cmd = "#{@cli} --verbose --config #{@project_root}/config/trident.yml"
      io = IO.popen(cmd, :err=>[:child, :out])

      wait_for(io, /<pool-mypool1> Pool started with 3 workers/)
      wait_for(io, /<pool-mypool2> Pool started with 2 workers/)

      processes = child_processes
      assert_equal 6, processes.size
      manager = processes[io.pid]
      pools = parse_manager(manager)
      children = pools['mypool1']
      child = children.delete_at(1)
      Process.kill("KILL", child)

      wait_for(io, /<pool-mypool1> Spawned worker \d+, worker count now at 3/)
      processes = child_processes
      assert_equal 6, processes.size
      manager = processes[io.pid]
      pools = parse_manager(manager)
      assert_equal 3, pools['mypool1'].size
      assert children.all? {|c| pools['mypool1'].include?(c) }

      Process.kill("USR1", io.pid)
      Process.wait(io.pid)
      assert_empty child_processes
    end
  end
end
