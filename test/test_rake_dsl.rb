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

  def test_toplevel_dsl_deprecated
    _, stderr = capture_io do
      TOPLEVEL_BINDING.instance_eval do
        task :something do
        end
      end
    end

    assert_match /Rake::DSL/, stderr, "Top Level DSL should be deprecated"
  end

  def test_dsl_toplevel_when_require_rake_dsl
    ruby '-I./lib', '-rrake/dsl', '-e', 'task(:x) { }', :verbose => false

    assert $?.exitstatus
  end
end
