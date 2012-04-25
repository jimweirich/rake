require 'thread'
require 'set'

module Rake
  class WorkerPool
    attr_accessor :maximum_size   # this is the maximum size of the pool

    def initialize(max = nil)
      @threads = Set.new          # this holds the set of threads in the pool
      @waiting_threads = Set.new  # set of threads waiting in #execute_blocks
      @threads_mutex = Mutex.new  # use this whenever r/w @threads
      @queue = Queue.new          # this holds blocks to be executed
      @join_cv = ConditionVariable.new # alerts threads sleeping from calling #join
      if (max && max > 0)
        @maximum_size = max
      else
        @maximum_size = (2**(0.size * 8 - 2) - 1) # FIXNUM_MAX
      end
    end

    def execute_blocks(blocks)
      mutex = Mutex.new
      cv = ConditionVariable.new
      exception = nil
      unprocessed_block_count = blocks.count
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
        was_in_set = @threads_mutex.synchronize {
          @waiting_threads.add(Thread.current)
          @threads.delete? Thread.current
        }
        ensure_thread_count(blocks.count)
        cv.wait(mutex) until unprocessed_block_count == 0
        @threads_mutex.synchronize {
          @waiting_threads.delete(Thread.current)
          @threads.add(Thread.current) if was_in_set
          # shutdown the thread pool if we were the last thread
          # waiting on the thread pool to process blocks
          join if @waiting_threads.count == 0
        }
      }
      # raise any exceptions that arose in the block (the last
      # exception won)
      raise exception if exception
    end

    def ensure_thread_count(count)
      # here, we need to somehow make sure to add as many threads as
      # are needed and no more. So (blocks.size - ready threads)
      @threads_mutex.synchronize {
        threads_needed = [[@maximum_size,count].min - @threads.size, 0].max
        threads_needed.times do
          t = Thread.new do
            begin
              while @threads.size <= @maximum_size
                @queue.deq.call
              end
            ensure
              @threads_mutex.synchronize {
                @threads.delete(Thread.current)
                @join_cv.signal
              }
            end
          end
          @threads.add t
        end
      }
    end
    private :ensure_thread_count
    
    def join
      # *** MUST BE CALLED inside @threads_mutex.synchronize{}
      # because we don't want any threads added while we wait, only
      # removed we set the maximum size to 0 and then add enough blocks
      # to the queue so any sleeping threads will wake up and notice
      # there are more threads than the limit and exit
      saved_maximum_size, @maximum_size = @maximum_size, 0
      @threads.each { @queue.enq lambda { ; } } # wake them all up

      # here, we sleep and wait for a signal off @join_cv
      # we will get it once for each sleeping thread so we watch the
      # thread count
      #
      # avoid the temptation to change this to
      # "<code> until <condition>". The condition needs to checked
      # first or you will deadlock.
      while (@threads.size > 0)
        @join_cv.wait(@threads_mutex)
      end
      
      # now everything has been executed and we are ready to
      # start accepting more work so we raise the limit back
      @maximum_size = saved_maximum_size
    end
    private :join

  end
end
