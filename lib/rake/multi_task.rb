require 'thread'
require 'set'

module Rake

  # Same as a regular task, but the immediate prerequisites are done in
  # parallel using Ruby threads.

  # MultiTasks load all their prerequisites onto a work queue (singleton
  # for the class) which is processed by a thread pool of variable size.
  # In order to prevent deadlocks, the current thread also processes
  # tasks on the queue until its prerequisite tasks are finished.

  class MultiTask < Task

    private
    def invoke_prerequisites(args, invocation_chain)
      blocks = @prerequisites.collect { |r| lambda{ application[r, @scope].invoke_with_call_chain(args, invocation_chain) } }

      if ( application.options.max_concurrent_jobs == nil )
        threads = blocks.collect { |block| Thread.new {block.call} }
        threads.each { |t| t.join }
        return
      end

      @@block_queue ||= Queue.new
      @@thread_pool ||= ThreadGroup.new

      block_count = blocks.count
      block_threads = Set.new
      blocks_info_semaphore = Mutex.new
      
      blocks.each do |block|
        @@block_queue.enq lambda {
          blocks_info_semaphore.synchronize { block_threads.add(Thread.current) }
          block.call
          blocks_info_semaphore.synchronize { block_threads.delete(Thread.current); block_count -= 1 }
        }
        
        if @@thread_pool.list.count < (application.options.max_concurrent_jobs - 1)
          @@thread_pool.add Thread.new { process_all_blocks }
        end
      end

      process_all_blocks_until { block_count == 0 }
      blocks_info_semaphore.synchronize { block_threads.dup }.each {|thread| thread.join}
      
    end
    
    def process_all_blocks_until
      begin
        while (!yield && something = @@block_queue.deq(true))
          something.call
        end
      rescue ThreadError
      end
    end
    
    def process_all_blocks
      process_all_blocks_until {false}
    end

  end
end
