require 'thread'
require 'set'

module Rake

  # Same as a regular task, but the immediate prerequisites are done in
  # parallel using Ruby threads.
  #
  # invoke_prerequisites delegates processing of the prerequisites to
  # threads in a thread pool until the thread pool is full.
  # Then, execution of the prerequisites synchronously continues on,
  # checking the size of the thread pool after each one just in case
  # another thread has exited and it can delegate again.
  #
  # When all the prerequisites have been called, the current thread
  # waits for the other threads processing the prerequisites
  #
  class MultiTask < Task
    private
    def invoke_prerequisites(args, invocation_chain) # :nodoc:
      @@thread_pool   ||= Set.new
      our_threads = Set.new
      mutex = Mutex.new

      @prerequisites.each do |p|
        block = lambda {
          application[p, @scope].invoke_with_call_chain(args, invocation_chain)
        }
        if ( @@thread_pool.size < application.options.thread_pool_size )
          mutex.synchronize {
            thread = Thread.new do
              block.call
              mutex.synchronize {
                our_threads.delete(thread)
                @@thread_pool.delete(thread)
              }
            end
            our_threads.add(thread)
            @@thread_pool.add(thread)
          }
        else
          block.call
        end
      end
      mutex.synchronize { our_threads.dup }.each { |t| t.join }
    end
  end
end
