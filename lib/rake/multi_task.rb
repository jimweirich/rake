require 'thread'
require 'set'

module Rake

  # Same as a regular task, but the immediate prerequisites are done in
  # parallel using Ruby threads.
  #
  # MultiTasks load all their prerequisites onto a work queue (singleton
  # for the class) which is processed by a thread pool of variable size.
  # In order to prevent deadlocks, the current thread also processes
  # tasks on the queue until its prerequisite tasks are finished.
  #
  class MultiTask < Task
    private
    def invoke_prerequisites(args, invocation_chain)
      @@block_queue ||= Queue.new

      block_count = @prerequisites.count
      block_threads = Set.new
      blocks_info_semaphore = Mutex.new
      
      @prerequisites.each do |r|
        @@block_queue.enq lambda {
          blocks_info_semaphore.synchronize { block_threads.add(Thread.current) }
          application[r, @scope].invoke_with_call_chain(args, invocation_chain)
          blocks_info_semaphore.synchronize { block_threads.delete(Thread.current); block_count -= 1 }
        }
      end

      process_all_blocks_until { block_count == 0 }
      blocks_info_semaphore.synchronize { block_threads.dup }.each {|thread| thread.join}
    end
    
    def process_all_blocks_until
      @@thread_pool ||= ThreadGroup.new
      begin
        while (!yield && something = @@block_queue.deq(true))
          # track the thread pool size
          if @@thread_pool.list.count < application.options.thread_pool_size
            @@thread_pool.add Thread.new {
              process_all_blocks_until { @@thread_pool.list.count > application.options.thread_pool_size}
            }
          end
          something.call
        end
      rescue ThreadError
      end
    end

  end
end
