require_relative '../test_helper'

class Trident::TridentTest < MiniTest::Should::TestCase

  setup do
    @project_root = File.expand_path('../../fixtures/integration_project', __FILE__)
    @cli = "#{File.expand_path('../../..', __FILE__)}/bin/trident"
  end

  def process_list
    processes = {}
    lines = `ps -e -opid,command`.lines.grep(/trident\[/)
    lines.each do |line|
      pieces = line.split
      pid = pieces[0].to_i
      next if pid == Process.pid
      command = pieces[1..-1].join(' ')
      processes[pid] = command
    end
    processes
  end

  def parse_manager(manager_str)
    pools = {}
    manager_str.scan(/(\w+)\[([0-9, ]+)\]/) do |pool, pids|
      pids = pids.split(", ").collect(&:to_i)
      pools[pool] = pids
    end
    pools
  end

  context "basic usage" do

    should "start and stop pools" do
      cmd = "#{@cli} --verbose --config #{@project_root}/config/trident.yml"
      io = IO.popen(cmd, :err=>[:child, :out])

      wait_for(io, /<pool-mypool1> Pool started with 3 workers/)
      wait_for(io, /<pool-mypool2> Pool started with 2 workers/)

      processes = process_list
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
      assert_empty process_list
    end

  end

  context "worker maintenance" do

    should "restart failed workers" do
      cmd = "#{@cli} --verbose --config #{@project_root}/config/trident.yml"
      io = IO.popen(cmd, :err=>[:child, :out])

      wait_for(io, /<pool-mypool1> Pool started with 3 workers/)
      wait_for(io, /<pool-mypool2> Pool started with 2 workers/)

      processes = process_list
      assert_equal 6, processes.size
      manager = processes[io.pid]
      pools = parse_manager(manager)
      children = pools['mypool1']
      child = children.delete_at(1)
      Process.kill("KILL", child)

      wait_for(io, /<pool-mypool1> Spawned worker \d+, worker count now at 3/)
      processes = process_list
      assert_equal 6, processes.size
      manager = processes[io.pid]
      pools = parse_manager(manager)
      assert_equal 3, pools['mypool1'].size
      assert children.all? {|c| pools['mypool1'].include?(c) }

      Process.kill("USR1", io.pid)
      Process.wait(io.pid)
      assert_empty process_list
    end

  end
end
