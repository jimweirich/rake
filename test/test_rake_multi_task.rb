require File.expand_path('../helper', __FILE__)
require 'thread'

class TestRakeMultiTask < Rake::TestCase
  include Rake
  include Rake::DSL

  def setup
    super

    Task.clear
    @runs = Array.new
    @mutex = Mutex.new
  end

  def add_run(obj)
    @mutex.synchronize do
      @runs << obj
    end
  end

  def test_running_multitasks
    task :a do 3.times do |i| add_run("A#{i}"); sleep 0.01; end end
    task :b do 3.times do |i| add_run("B#{i}"); sleep 0.01;  end end
    multitask :both => [:a, :b]
    Task[:both].invoke
    assert_equal 6, @runs.size
    assert @runs.index("A0") < @runs.index("A1")
    assert @runs.index("A1") < @runs.index("A2")
    assert @runs.index("B0") < @runs.index("B1")
    assert @runs.index("B1") < @runs.index("B2")
  end

  def test_all_multitasks_wait_on_slow_prerequisites
    task :slow do 3.times do |i| add_run("S#{i}"); sleep 0.05 end end
    task :a => [:slow] do 3.times do |i| add_run("A#{i}"); sleep 0.01 end end
    task :b => [:slow] do 3.times do |i| add_run("B#{i}"); sleep 0.01 end end
    multitask :both => [:a, :b]
    Task[:both].invoke
    assert_equal 9, @runs.size
    assert @runs.index("S0") < @runs.index("S1")
    assert @runs.index("S1") < @runs.index("S2")
    assert @runs.index("S2") < @runs.index("A0")
    assert @runs.index("S2") < @runs.index("B0")
    assert @runs.index("A0") < @runs.index("A1")
    assert @runs.index("A1") < @runs.index("A2")
    assert @runs.index("B0") < @runs.index("B1")
    assert @runs.index("B1") < @runs.index("B2")
  end
  
  #Test the handling of prerequisite invocation when the list 
  #of prerequisites for a task is changed by a prerequisite
  def test_dynamic_prerequisites
    runlist = []
    t1 = multitask(:t1 => [:t2]) { |t| runlist << t.name; 3321 }
    t2 = multitask(:t2) { |t| task :t1=>:t3; runlist << t.name }
    #although it adds a prerequisite to t2 it will do so after t2 is executed
    t3 = multitask(:t3) { |t| task :t2=>:t4; runlist << t.name }
    t4 = multitask(:t4) { |t| runlist << t.name }
    assert_equal ["t2"], t1.prerequisites
    assert_equal [], t2.prerequisites
    t1.invoke
    assert_equal ["t2","t3"], t1.prerequisites
    #so, these have changed but not in time
    #so you can't change prereqs on the same level
    assert_equal ["t4"], t2.prerequisites
    #but changing the prereqs of the "parent" works
    assert_equal ["t2", "t3", "t1"], runlist
  end
end

