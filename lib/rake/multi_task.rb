module Rake

  # Same as a regular task, but the immediate prerequisites are done in
  # parallel using Ruby threads.
  #
  class MultiTask < Task
    private
    def invoke_prerequisites(args, invocation_chain)
      original_size=prerequisite_tasks.size
      threads = @prerequisites.collect { |p|
        Thread.new(p) { |r| application[r, @scope].invoke_with_call_chain(args, invocation_chain) }
      }
      threads.each { |t| t.join }
      invoke_prerequisites(args, invocation_chain) if prerequisite_tasks.size != original_size
    end
  end

end
