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
        opts.banner = "Usage: rake -- #{name} [options] #{arg_names.join(' ')}"
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

    def config
      @config ||= {}
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
    end

    def parse_options(obj)
      case obj
      when Array  then [obj]
      else nil
      end
    end

    def set_options(options)
      options.each do |(key, default, *option)|
        default = false if default.nil?
        option = guess_option(key, default) if option.empty?

        config[key.to_sym] = default
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
      case default
      when false
        ["--#{key}"]
      when true
        ["--[no-]#{key}"]
      else
        ["--#{key} [#{key.to_s.upcase}]"]
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