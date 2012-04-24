require 'rake/worker_pool'

module Rake

  # Same as a regular task, but the immediate prerequisites are done in
  # parallel using Ruby threads.
  #
  class MultiTask < Task
    private
    def invoke_prerequisites(args, invocation_chain)
      @@wp ||= WorkerPool.new
    
      blocks = @prerequisites.collect { |r|
        lambda { application[r, @scope].invoke_with_call_chain(args, invocation_chain) }
      }
      @@wp.execute_blocks blocks
    end
  end

end
