require File.expand_path('../helper', __FILE__)
require 'fileutils'

class TestRakeDirectoryTask < Rake::TestCase
  include Rake

  def test_directory
    desc "DESC"

    directory "a/b/c"

    assert_equal FileCreationTask, Task["a"].class
    assert_equal FileCreationTask, Task["a/b"].class
    assert_equal FileCreationTask, Task["a/b/c"].class

    assert_nil             Task["a"].comment
    assert_nil             Task["a/b"].comment
    assert_equal "DESC",   Task["a/b/c"].comment

    verbose(false) {
      Task['a/b'].invoke
    }

    assert File.exist?("a/b")
    refute File.exist?("a/b/c")
  end

  def test_lookup_ignores_trailing_slash
    Dir.mkdir "a"

    # Since "a" exists, if we lookup "a", TaskManager creates an
    # implicit FileTask (barring any other tasks named "a")
    refute Task.task_defined? "a"
    assert_instance_of Rake::FileTask, Task["a"]
    assert Task.task_defined? "a"

    # Rake.each_dir_parent will yield "a/"
    directory "a/"

    # "a" and "a/" should both point to the FileCreationTask defined
    # by the directory task
    assert_instance_of Rake::FileCreationTask, Task["a/"]

    refute_instance_of Rake::FileTask,         Task["a"]
    assert_instance_of Rake::FileCreationTask, Task["a"]
  end
end
