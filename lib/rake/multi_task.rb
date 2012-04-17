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

    @@multi_task_queue = Queue.new
    @@thread_group = ThreadGroup.new

    def invoke_prerequisites(args, invocation_chain)
      if ( application.options.max_concurrent_jobs == nil )
        invoke_prerequisites_unlimited_threads(args, invocation_chain)
      else
        invoke_prerequisites_thread_limit(args, invocation_chain, application.options.max_concurrent_jobs)
      end
    end

    def invoke_prerequisites_unlimited_threads(args, invocation_chain)
      threads = @prerequisites.collect { |p|
        Thread.new(p) { |r| application[r, @scope].invoke_with_call_chain(args, invocation_chain) }
      }
      threads.each { |t| t.join }
    end

    def invoke_prerequisites_thread_limit(args, invocation_chain, max_concurrent_jobs)

      unfinished_task_count = 0
      unfinished_task_threads = Set.new
      unfinished_task_semaphore = Mutex.new
      
      @prerequisites.each do |r|
        unfinished_task_semaphore.synchronize { unfinished_task_count += 1 }

        @@multi_task_queue.enq lambda {
          unfinished_task_semaphore.synchronize { unfinished_task_threads.add Thread.current }

          application[r, @scope].invoke_with_call_chain(args, invocation_chain)

          unfinished_task_semaphore.synchronize { unfinished_task_count -= 1; unfinished_task_threads.delete Thread.current}
        }
        
        # Here, we only create a new thread if we are under the max number of threads
        if @@thread_group.list.count < max_concurrent_jobs
          @@thread_group.add Thread.new {
            begin

              while something = @@multi_task_queue.deq(true)
                something.call
              end

            rescue ThreadError
              # We are here because there was nothing left on the queue so we exit
            end
          }
        end

      end

      # while we wait for our tasks to complete, we process tasks
      # ourselves to avoid deadlock.
      # If there are no more blocks for use to execute and our tasks
      # are stil not completed, it's because there are other threads
      # still working on our tasks. Since we know the set of threads
      # that are currently working on our tasks
      # (unfinished_task_threads) we join them and wait for them to
      # finish
      
      while (unfinished_task_count > 0)
        begin

          while something = @@multi_task_queue.deq(true)
            something.call
          end
        rescue ThreadError
            # We are here because there was nothing left on the queue so we wait for
            # threads processing our prerequisites
            threads_copy = nil
            unfinished_task_semaphore.synchronize { threads_copy = unfinished_task_threads.dup }
            threads_copy.each {|thread| thread.join}
        end
      end
      
    end # @prerequisites.each
  end # invoke_prerequisites_thread_limit
end # Rake
