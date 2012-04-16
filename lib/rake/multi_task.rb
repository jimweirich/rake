require 'thread'
require 'set'

module Rake

  # Same as a regular task, but the immediate prerequisites are done in
  # parallel using Ruby threads.
  #
  class MultiTask < Task
    @@multi_task_queue = Queue.new
    @@thread_group = ThreadGroup.new
  
    private

    def invoke_prerequisites(args, invocation_chain)

        # bookkeeping
        bookkeeping_task_count = 0
        bookkeeping_threads = Set.new
        bookkeeping_semaphore = Mutex.new
        
        @prerequisites.each do |r|

          bookkeeping_semaphore.synchronize { bookkeeping_task_count += 1 }

          @@multi_task_queue.push lambda {

            bookkeeping_semaphore.synchronize { bookkeeping_threads.add Thread.current }

            application[r, @scope].invoke_with_call_chain(args, invocation_chain)

            bookkeeping_semaphore.synchronize { 
              bookkeeping_task_count -= 1
              bookkeeping_threads.delete Thread.current
            }
          }
          
          # Here, we only create a new thread if we are under the max number of threads
          if @@thread_group.list.count >= 16
            next
          end

          @@thread_group.add Thread.new {
            begin

              while something = @@multi_task_queue.pop(true)
                something.call
              end

            rescue ThreadError
            end
          }
        end

        # while we wait for our tasks to complete, we process tasks ourselves to avoid
        # deadlock.
        # If there are no more blocks for use to execute and our tasks are stil not
        # completed, it's because there are other threads still working on our tasks
        # since we know the set of threads that are currently working on our tasks
        # we join them and wait for them to finish
        
        while (bookkeeping_task_count > 0)
            begin

              while something = @@multi_task_queue.pop(true)
                something.call
              end
            rescue ThreadError
                threads_copy = nil
                bookkeeping_semaphore.synchronize { threads_copy = bookkeeping_threads.dup }
                threads_copy.each {|thread| thread.join}
            end
        end
    end
  end

end
