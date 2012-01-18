module Rake

  # Same as a regular task, but the immediate prerequisites are done in
  # parallel using Ruby threads.
  #
  class MultiTask < Task
    private
    def invoke_prerequisites(args, invocation_chain)
      original=prerequisite_tasks.dup
      invoke_prerequisite_list(prerequisite_tasks,args,invocation_chain)
      invoke_prerequisite_list(prerequisite_tasks-original,args,invocation_chain)
    end
    def invoke_prerequisite_list prereqs,args,invocation_chain
      threads = prereqs.collect { |p|
        Thread.new(p) { |r| application[r, @scope].invoke_with_call_chain(args, invocation_chain) }
      }
      threads.each { |t| t.join }
    end
  end
end
