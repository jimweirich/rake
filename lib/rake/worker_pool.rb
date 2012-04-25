require 'thread'
require 'set'

module Rake
  class WorkerPool
    attr_accessor :maximum_size   # this is the maximum size of the pool

    def initialize(max = nil)
      @threads = Set.new          # this holds the set of threads in the pool
      @threads_mutex = Mutex.new  # use this whenever r/w @threads
      @queue = Queue.new          # this holds blocks to be executed
      if (max && max > 0)
        @maximum_size= max
      else
        @maximum_size= 2          # why bother if it's not at least 2?
      end
    end

    def execute_blocks(blocks)
      mutex = Mutex.new
      cv = ConditionVariable.new
      exception = nil
      unprocessed_block_count = blocks.size
      mutex.synchronize {
        blocks.each { |block|
          @queue.enq lambda {
            begin
              block.call
            rescue Exception => e
              exception = e
            ensure
              # we *have* to have this 'ensure' because we *have* to
              # call cv.signal to wake up WorkerPool#execute_blocks
              # which is asleep because it called cv.wait(mutex)
              mutex.synchronize { unprocessed_block_count -= 1; cv.signal }
            end
          }
        }
        was_in_set = @threads_mutex.synchronize { @threads.delete? Thread.current }
        ensure_enough_threads
        cv.wait(mutex) until unprocessed_block_count == 0
        @threads_mutex.synchronize { @threads.add Thread.current } if was_in_set
      }
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
      if exception
        exception.set_backtrace exception.backtrace.concat(caller)
        raise exception
      end
    end

    def ensure_enough_threads
      # here, we need to somehow make sure to add as many threads as
      # are needed and no more. So (blocks.size - ready threads)
      @threads_mutex.synchronize {
        threads_needed = [@maximum_size - @threads.size, 0].max
        threads_needed.times do
          t = Thread.new do
            begin
              while @threads.size <= @maximum_size
                @queue.deq.call
              end
            ensure
              @threads_mutex.synchronize { @threads.delete(Thread.current) }
            end
          end
          @threads.add t
        end
      }
    end
    private :ensure_enough_threads
    
  end
end
