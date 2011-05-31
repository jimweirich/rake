require File.expand_path('../helper', __FILE__)

class TestRakeDsl < Rake::TestCase

  def test_namespace_command
    namespace "n" do
      task "t"
    end
    refute_nil Rake::Task["n:t"]
  end

  def test_namespace_command_with_bad_name
    ex = assert_raises(ArgumentError) do
      namespace 1 do end
    end
    assert_match(/string/i, ex.message)
    assert_match(/symbol/i, ex.message)
  end

  def test_namespace_command_with_a_string_like_object
    name = Object.new
    def name.to_str
      "bob"
    end
    namespace name do
      task "t"
    end
    refute_nil Rake::Task["bob:t"]
  end

  class Foo
    def initialize
      task :foo_deprecated_a => :foo_deprecated_b do
        print "a"
      end
      task :foo_deprecated_b do
        print "b"
      end
    end
  end

  def test_deprecated_object_dsl
    out, err = capture_io do
      Foo.new
      Rake.application.invoke_task :foo_deprecated_a
    end
    assert_equal("ba", out)
    assert_match(/deprecated/, err)
    assert_match(/Foo\#task/, err)
  end
end
