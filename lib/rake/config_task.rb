require 'rake/task.rb'
require 'optparse'

module Rake
  # #########################################################################
  # A ConfigTask is a task that allows simple command line configurations to
  # be passed to it.  Configurations are parsed as options from the task args.
  #
  class ConfigTask < Task

    # An OptionParser containing the configs for self.
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

    # Guess the option declaration for a config given a key and default
    # value, according to the following logic:
    #
    #   default     opt
    #   false       ['--key']
    #   true        ['--[no-]key']
    #   (obj)       ['--key KEY']
    #
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