module Rake

  # Same as a regular task, but the immediate prerequisites are done in
  # parallel using Ruby threads.
  #
  class MultiTask < Task
    private
    def invoke_prerequisite_list prereqs,args,invocation_chain
      threads = prereqs.collect { |p|
        Thread.new(p) { |r| application[r, @scope].invoke_with_call_chain(args, invocation_chain) }
      }
      threads.each { |t| t.join }
    end
  end
end
