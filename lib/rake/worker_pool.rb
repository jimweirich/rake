require 'thread'
require 'set'

module Rake
  class WorkerPool
    attr_accessor :maximum_size   # this is the maximum size of the pool

    def initialize(max = nil)
      @threads = Set.new          # this holds the set of threads in the pool
      @ready_threads = Set.new    # this holds the set of threads awaiting work
      @threads_mutex = Mutex.new  # use this whenever r/w @threads, @ready_threads
      @queue = Queue.new          # this holds blocks to be executed
      @wait_cv = ConditionVariable.new # alerts threads sleeping from calling #wait
      if (max && max > 0)
        @maximum_size= max
      else
        @maximum_size= (2**(0.size * 8 - 2) - 1) # FIXNUM_MAX
      end
    end

    def execute_blocks(blocks)
      mutex = Mutex.new
      cv = ConditionVariable.new
      exception = nil
      remaining = blocks.size
      mutex.synchronize {
        blocks.each { |block|
          @queue.enq lambda {
            begin
              block.call
            rescue Exception => e
              exception = e
            ensure
              # we *have* to have this 'ensure' because we *have* to
              # call cv.signal to wake up WorkerPool#execute_block
              # which is asleep because it called cv.wait(mutex)
              mutex.synchronize { remaining -= 1; cv.signal }
            end
          }
          add_thread
        }
        while remaining > 0
          cv.wait(mutex)
        end
      }
      if exception
        # IMPORTANT: In order to trace execution through threads,
        # we concatenate the backtrace of the exception (thrown in a
        # different context), with the backtrace of the
        # current context. In this way, you can see the backtrace
        # all the way through from when you called #execute_block
        # to where it was raised in the thread that was executing
        # that block.
        #
        # backtrace looks like this:
        #   exception.backtrace (in original thread context)
        #            |
        #            |
        #   caller (in our context)
        #
        # TODO: remove all portions of the backtrace that involve this
        #       file, but retain a list of full backtraces (in order)
        #       for the exception in each context. add (or use) an
        #       inspec method that shows the list of full backtraces
        exception.set_backtrace exception.backtrace.concat(caller)
        raise exception
      end
    end

    def execute_block(&block)
      execute_blocks [block]
    end
    
    def add_thread
      @threads_mutex.synchronize {
        if @threads.size >= @maximum_size || @ready_threads.size > 0
          next
        end
        t = Thread.new do
          begin
            while @threads.size <= @maximum_size
              @threads_mutex.synchronize{ @ready_threads.add(Thread.current) }
              @queue.deq.call
              @threads_mutex.synchronize{ @ready_threads.delete(Thread.current) }
            end
          ensure
            # we *have* to have this 'ensure' because we *have* to
            # call @wait_cv.signal. This wakes up the Thread
            # that is sleeping because it called WorkerPool#wait
            @threads_mutex.synchronize{
              @ready_threads.delete(Thread.current)
              @threads.delete(Thread.current)
              @wait_cv.signal
            }
          end
        end
        @threads.add t
      }
    end
    private :add_thread
    
  end
end
