module Rake
  module Backtrace
    SUPPRESS_PATHS = [
      RbConfig::CONFIG["prefix"],
      File.join(File.dirname(__FILE__), ".."),
    ]
  
    #
    # Elide backtrace elements which match one of SUPPRESS_PATHS.
    #
    def self.collapse(backtrace)
      paths = SUPPRESS_PATHS.map { |f| Regexp.quote File.expand_path(f) }
  
      # add bin/rake for rake testing
      suppress_re = %r!(\A#{paths.join('|')}|bin/rake:\d+)!
  
      result = backtrace.map { |elem|
        if elem =~ suppress_re
          "[...suppressed backtrace...]"
        else
          elem
        end
      }
  
      remove_repeats(result)
    end
  
    #
    # Remove consecutive matches.
    #
    # remove_repeats [3, 3, 9, 3, 1, 1, 1, 4, 9, 9]  # => [3, 9, 3, 1, 4, 9]
    #
    def self.remove_repeats(array)
      result = []
      prev = nil
      array.each_with_index do |elem, i|
        if i == 0 or elem != prev
          result << elem
        end
        prev = elem
      end
      result
    end
  end
end
