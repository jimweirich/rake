module Rake
  CACHE_DIR = File.expand_path ".cache" unless defined? CACHE_DIR
  # TODO: add checksum support
  class RemotePackage < Rake::Task
    include Rake::DSL if defined? Rake::DSL

    # Support for special github tarballs
    GITHUB_MATCH = %r[^https?://github\.com/([^/]+)/([^/]+)/(zip|tar)ball/(.*)]

    def needed?
      ! File.exists?(local_path)
    end

    def local_path
      File.join(CACHE_DIR, "pkg", basename)
    end

    def basename
      if name =~ GITHUB_MATCH
        "#{$1}-#{$2}-#{$4}#{$3 == "zip" ? ".zip" : ".tar.gz"}"
      else
        File.basename(name.sub(/\?.*/,''))
      end
    end

    def execute(args=nil)
      FileUtils.mkdir_p File.dirname(local_path)
      sh "curl -L -o \"#{local_path}.tmp\" \"#{name}\""
      mv "#{local_path}.tmp", local_path
      super
    end

    # Utility
    def unpack_to(dir)
      abs_local_path = File.expand_path(local_path)
      Dir.chdir(dir) do
        case abs_local_path
        when /\.tar\.gz$/, /\.tgz$/
          sh "tar xzvf \"#{abs_local_path}\""
        when /\.tar\.bz2$/
          sh "tar xjvf \"#{abs_local_path}\""
        when /\.tar$/
          sh "tar xvf \"#{abs_local_path}\""
        else
          raise "Unsupported file extensions of #{basename}"
        end
      end
    end

    # Time stamp for file task.
    def timestamp
      if File.exist?(local_path)
        File.mtime(local_path.to_s)
      else
        Rake::EARLY
      end
    end

    class << self
      # Apply the scope to the task name according to the rules for this kind
      # of task.  File based tasks ignore the scope when creating the name.
      def scope_name(scope, task_name)
        task_name
      end
    end
  end
end

# FIXME: where do I put that ?
#
# Usage example:
#     ref = remote_package("http://downloads.sf.net/...")
#
#     build_dir = directory "build/dir"
#
#     task :build => [ref, build_dir] do
#       ref.unpack_to(build_dir)
#     end
#
def remote_package(*args, &block)
  t = Rake::RemotePackage.define_task(*args, &block)
  Rake::Task["remote_packages"].prerequisites.push(t.name).uniq!
  t
end

# FIXME: and that ?
desc "Downloads all remote packages"
task :remote_packages
