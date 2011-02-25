require 'rake/task.rb'
require 'optparse'

module Rake
  # #########################################################################
  # = ConfigTask
  # 
  # Config tasks allow the creation of tasks that can recieve simple
  # configurations using command line options. The intention is to allow
  # command-like tasks to be defined and used in a natural way (ie using a 'name
  # --flag arg' syntax). For clarity ConfigTasks are declared using 'tasc' and
  # referred to as 'tascs'.
  # 
  # Tasc configs are declared using an options string and accessed on the tasc
  # itself. Numeric types are cast to appropriate values.
  # 
  #   require 'rake'
  # 
  #   desc "welcome a thing"
  #   tasc :welcome, :thing, %{
  #     -m,--message [hello]  : A welcome message
  #     -n [1]                : Number of times to repeat
  #   } do |config, args|
  #     config.n.times do 
  #       puts "#{config.message} #{args.thing}"
  #     end
  #   end
  # 
  # Then from the command line, invoke after '--':
  # 
  #   % rake -- welcome world
  #   hello world
  #   % rake -- welcome --message goodnight -n 3 moon
  #   goodnight moon
  #   goodnight moon
  #   goodnight moon
  #   % rake -- welcome --help
  #   Usage: rake -- welcome [options] object
  #       -m, --message [hello]            A welcome message
  #       -n [1]                           Number of times to repeat
  #       -h, --help                       Display this help message.
  # 
  # Unlike typical tasks which only run once, tascs are reset after each run, so
  # that they can be invoked multiple times:
  # 
  #   % rake -- welcome world -- welcome moon -m goodnight
  #   hello world
  #   goodnight moon
  # 
  # Tascs may participate in dependency workflows, although it gets a little
  # peculiar when other tasks depend upon the tasc. Below is an explanation.
  # TL;DR; -- tascs may have dependencies, but other tasks/tascs should not depend
  # upon a tasc.
  # 
  # == Dependency Discussion
  # 
  # Normally tasks are designed to be unaware of context (for lack of a better
  # word). Once you introduce arguments/configs, then suddenly it matters when the
  # arguments/configs 'get to' a task. For example:
  # 
  #   require 'rake'
  # 
  #   task(:a) { puts 'a' }
  #   task(:b => :a) { puts 'b' }
  # 
  #   tasc(:x, [:letter, 'x']) {|t| puts t.letter }
  #   tasc(:y, [:letter, 'y'], :needs => :x) {|t| puts t.letter }
  # 
  # There is no order issue for the tasks, for which there is no context and
  # therefore they can align into a one-true execution order regardless of
  # declaration order.
  # 
  #   % rake a b
  #   a
  #   b
  #   % rake b a
  #   a
  #   b
  # 
  # A problem arises, however with tascs that do have a context. Now it matters
  # what order things get declared in. For example:
  # 
  #   % rake -- x --letter a -- y --letter b
  #   a
  #   a
  #   b
  #   % rake -- y --letter b -- x --letter a
  #   x
  #   b
  #   a
  # 
  # You can see that declaration order matters for tascs in a way it does not for
  # tasks. The problem is not caused directly by the decision to make tascs run
  # multiple times; it's caused by the context which gets interwoven to all
  # tasks/tascs via dependencies. For example, pretend tascs only executed once...
  # which arguments/configurations should win in this case?
  # 
  #   % rake -- welcome world -- welcome -m goodnight
  #   # hello world ?
  #   # goodnight ?
  #   # goodnight world ?
  # 
  # All of this can be avoided by only using tascs as end-points for dependency
  # workflows and never as prerequisites. This is fine:
  # 
  #   require 'rake'
  # 
  #   task(:a) { print 'a' }
  #   task(:b => :a) { print 'b' }
  #   tasc(:x, [:letter, 'x'], :needs => [:b, :a]) {|t| puts t.letter }
  # 
  # Now:
  # 
  #   % rake -- x --letter c
  #   abc
  #   % rake a b -- x --letter c
  #   abc
  #   % rake b a -- x --letter c
  #   abc
  # 
  class ConfigTask < Task

    def parser
      @parser ||= OptionParser.new do |opts|
        opts.on_tail("-h", "--help", "Display this help message.") do
          puts opts
          exit
        end
      end
    end

    def invoke(*args)
      parser.parse!(args)
      super(*args)
    end

    def invoke_with_call_chain(*args)
      super
      reenable
    end

    def reenable
      @config = nil
      super
    end

    def config
      @configs ||= default_config.dup
    end

    def default_config
      @default_config ||= {}
    end

    def [](key)
      config[key.to_sym]
    end

    def method_missing(sym, *args, &block)
      sym = sym.to_sym
      config.has_key?(sym) ? config[sym] : super
    end

    def set_arg_names(args)
      while options = parse_options(args.last)
        set_options(options)
        args.pop
      end
      @arg_names = args.map { |a| a.to_sym }
      parser.banner = "Usage: rake -- #{name} [options] #{@arg_names.join(' ')}"
      @arg_names
    end

    def parse_options(obj)
      case obj
      when Array  then [obj]
      when String then parse_options_string(obj)
      else nil
      end
    end

    def parse_options_string(string)
      string = string.strip
      return nil unless string[0] == ?-
      
      string.split(/\s*\n\s*/).collect do |str|
        flags, desc = str.split(':', 2)
        flags = flags.split(',').collect! {|arg| arg.strip }
        
        key = guess_key(flags) 
        default = flags.last =~ /\s+\[(.*)\]/ ? guess_default($1) : guess_bool_default(flags)
        
        [key, default] + flags + [desc.to_s.strip]
      end
    end

    def guess_key(flags)
      keys = flags.collect do |flag|
        case flag.split(' ').first
        when /\A-([^-])\z/       then $1
        when /\A--\[no-\](.*)\z/ then $1
        when /\A--(.*)\z/        then $1
        else nil
        end
      end
      keys.compact.sort_by {|key| key.length }.last
    end

    def guess_default(str)
      case str
      when /\A(\d+)\z/ then str.to_i
      when /\A(\d+\.\d+)\z/ then str.to_f
      else str
      end
    end

    def guess_bool_default(flags)
      flags.any? {|flag| flag =~ /\A--\[no-\]/ ? true : false }
    end

    def set_options(options)
      options.each do |(key, default, *option)|
        default = false if default.nil?
        option = guess_option(key, default) if option.empty?

        default_config[key.to_sym] = default
        parser.on(*option) do |value|
          config[key.to_sym] = parse_config_value(default, value)
        end
      end
    end

    def guess_option(key, default)
      n = key.to_s.length
      
      case default
      when false
        n == 1 ? ["-#{key}"] : ["--#{key}"]
      when true
        ["--[no-]#{key}"]
      else
        n == 1 ? ["-#{key} [#{key.to_s.upcase}]"] : ["--#{key} [#{key.to_s.upcase}]"]
      end
    end

    def parse_config_value(default, value)
      case default
      when String  then value.to_s
      when Integer then value.to_i
      when Float   then value.to_f
      else value
      end
    end
  end
end