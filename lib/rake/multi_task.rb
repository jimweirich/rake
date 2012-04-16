require 'thread'
require 'set'

module Rake

  # Same as a regular task, but the immediate prerequisites are done in
  # parallel using Ruby threads.

  # MultiTasks load all their prerequisites onto a work queue (singleton
  # for the class) which is processed by a thread pool of variable size.
  # In order to prevent deadlocks, the current thread also processes
  # tasks on the queue until its prereqeusite tasks are finished.

  class MultiTask < Task

    private

    @@multi_task_queue = Queue.new
    @@thread_group = ThreadGroup.new

    def invoke_prerequisites(args, invocation_chain)

        # bookkeeping
        unfinished_task_count = 0
        unfinished_task_threads = Set.new
        unfinished_task_semaphore = Mutex.new
        
        @prerequisites.each do |r|

          unfinished_task_semaphore.synchronize { unfinished_task_count += 1 }

          @@multi_task_queue.enq lambda {

            unfinished_task_semaphore.synchronize { unfinished_task_threads.add Thread.current }

            application[r, @scope].invoke_with_call_chain(args, invocation_chain)

            unfinished_task_semaphore.synchronize { 
              unfinished_task_count -= 1
              unfinished_task_threads.delete Thread.current
            }
          }
          
          # Here, we only create a new thread if we are under the max number of threads

          if @@thread_group.list.count < 16
            @@thread_group.add Thread.new {
              begin
  
                while something = @@multi_task_queue.deq(true)
                  something.call
                end
  
              rescue ThreadError
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
                threads_copy = nil
                unfinished_task_semaphore.synchronize { threads_copy = unfinished_task_threads.dup }
                threads_copy.each {|thread| thread.join}
            end
        end
    end
  end

end
