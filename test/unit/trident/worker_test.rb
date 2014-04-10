require_relative '../../test_helper'

class Trident::WorkerTest < MiniTest::Should::TestCase

  setup do
    @pool = mock('pool')
    @pool.stubs(:orphans_dir).returns(Dir.tmpdir)

    @worker = Worker.new(123, @pool)
  end

  teardown do
    @worker.destroy if File.exists?(@worker.send(:path))
  end
  
  context "save" do
    should "write its pid to a file" do
      @worker.save
      pidfile = File.join(@pool.orphans_dir, '123.pid') 
      assert File.exists?(pidfile)
      assert_equal '123', File.read(pidfile)
    end
  end

  context "destroy" do
    should "remove its file" do
      @worker.save

      pidfile = File.join(@pool.orphans_dir, '123.pid') 
      assert File.exists?(pidfile)

      @worker.destroy
      refute File.exists?(pidfile)
    end
  end

  context "created_at" do
    should "return creation time" do
      @worker.save

      pidfile = File.join(@pool.orphans_dir, '123.pid') 
      assert_equal @worker.created_at, File.stat(pidfile).ctime
    end
  end
end
