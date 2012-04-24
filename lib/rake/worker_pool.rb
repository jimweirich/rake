require 'thread'
require 'set'

module Rake
  class WorkerPool
    attr_accessor :maximum_size   # this is the maximum size of the pool

    def initialize(max = nil)
      @threads = Set.new          # this holds the set of threads in the pool
      @threads_mutex = Mutex.new  # use this whenever r/w @threads
      @queue = Queue.new          # this holds blocks to be executed
      @wait_cv = ConditionVariable.new # alerts threads sleeping from calling #wait
      if (max && max > 0)
        self.maximum_size= max
      else
        self.maximum_size= (2**(0.size * 8 - 2) - 1) # FIXNUM_MAX
      end
    end

    def execute_block(&block)
      mutex = Mutex.new
      cv = ConditionVariable.new
      exception = nil
      
      mutex.synchronize {
        @queue.enq lambda {
          begin
            block.call
          rescue Exception => e
            exception = e
          ensure
            # we *have* to have this 'ensure' because we *have* to
            # call cv.signal to wake up WorkerPool#execute_block
            # which is asleep because it called cv.wait(mutex)
            mutex.synchronize{ cv.signal }
          end
        }
        add_thread
        cv.wait(mutex)
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
        exception.set_backtrace exception.backtrace.concat(caller)
        raise exception
      end
    end
    
    def add_thread
      @threads_mutex.synchronize {
        if @threads.size >= self.maximum_size
          next
        end
        t = Thread.new do
          begin
            while @threads.size <= self.maximum_size
              @queue.deq.call
            end
          ensure
            # we *have* to have this 'ensure' because we *have* to
            # call @wait_cv.signal. This wakes up the Thread
            # that is sleeping because it called WorkerPool#wait
            @threads_mutex.synchronize{
              @threads.delete(Thread.current)
              @wait_cv.signal
            }
          end
        end
        @threads.add t
      }
    end
    private :add_thread
    
    def wait
      # we synchronize on @threads_mutex because we don't want
      # any threads added while we wait, only removed
      # we set the maximum size to 0 and then add enough blocks to the
      # queue so any sleeping threads will wake up and notice there are
      # more threads than the limit and exit
      @threads_mutex.synchronize {
        saved_maximum_size, @maximum_size = @maximum_size, 0
        @threads.each { @queue.enq lambda { ; } } # wake them all up
        # here, we sleep and wait for a signal off @wait_cv
        # we will get it once for each sleeping thread so we watch the
        # thread count
        while (@threads.size > 0)
          @wait_cv.wait(@threads_mutex)
        end
        
        # now everything has been executed and we are ready to
        # start accepting more work so we raise the limit back
        @maximum_size = saved_maximum_size
      }
    end

  end
end
