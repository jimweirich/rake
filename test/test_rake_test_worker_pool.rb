require File.expand_path('../helper', __FILE__)
require 'rake/worker_pool'
require 'test/unit/assertions'

class TestRakeTestWorkerPool < Rake::TestCase
  include Rake
  
  def test_block_order
    mx = Mutex.new
    block = lambda {|executor,count=20,result=""|
      return if (count < 1)
      mx.synchronize{ result << count.to_s }
      sleep(rand * 0.01)
      executor.call( [lambda {block.call(executor,count-1,result)}] )
      result
    }

    old = lambda {|b|
        threads = b.collect {|c| Thread.new(c) {|d| d.call } }
        threads.each {|t| t.join }
    }

    wp = WorkerPool.new(4)
    new = lambda {|b| wp.execute_blocks b }
    
    assert_equal(block.call(old), block.call(new))
  end

  # test that there are no deadlocks within the worker pool itself
  def test_deadlocks
    wp = WorkerPool.new(10)
    blocks = []
    10.times {
       inner_block = lambda {|count=5|
        return if (count < 1)
        sleep(rand * 0.000001)
        inner_blocks = []
        3.times {  inner_blocks << lambda {inner_block.call(count-1)} }
        wp.execute_blocks inner_blocks
      }
      blocks << inner_block
    }
    wp.execute_blocks blocks
  end

  # test that throwing an exception way down in the blocks propagates
  # to the top
  def test_exceptions
    wp = WorkerPool.new(4)
    deep_exception_block = lambda {|count=3|
      raise Exception.new if ( count < 1 )
      deep_exception_block.call(count-1)
    }
    assert_raises(Exception) do
      wp.execute_blocks [deep_exception_block]
    end
  end

  def test_thread_count
    mutex = Mutex.new
    expected_thread_count = 2
    wp = WorkerPool.new(expected_thread_count)

    # the lambda code will determine how many threads are running in
    # the pool
    blocks = []
    thread_count = 0
    should_sleep = true
    (expected_thread_count*2).times do
      blocks << lambda {
        mutex.synchronize do; stack_prefix = "#{__FILE__}:#{__LINE__}" # this synchronize will be on the stack
          sleep 1 if should_sleep # this lets all the threads wait on the mutex
          threads = Thread.list
          backtraces = threads.collect {|t| t.backtrace}
          # sometimes a thread doesn't return a thread count
          if ( threads.count == backtraces.count )
            should_sleep = false
            # finds all the backtraces that contain our mutex.synchronize call
            our_bt = backtraces.find_all{|bt| bt && bt.index{|tr| tr.start_with? stack_prefix}!=nil }
            thread_count = [thread_count, our_bt.count].max
          end
        end
      }
    end
    
    wp.execute_blocks blocks
    assert_equal(expected_thread_count, thread_count)
  end
end

