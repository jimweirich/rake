#!/usr/bin/env ruby

require 'test/unit'
require 'rake'

######################################################################
# Note that this class is named oddly to fix an order issue in the tests. 
# When named without the 'Z', a TestClean test fails like so:
#
# test_clean(TestClean):
# RuntimeError: Don't know how to build task 'clean'
#     ./lib/rake/task_manager.rb:49:in `[]'
#     ./lib/rake/task.rb:298:in `[]'
#     ./test/lib/clean_test.rb:10:in `test_clean'
#
class ZConfigFileTask < Test::Unit::TestCase
  include Rake

  def setup
    super
    Task.clear
    Rake::TaskManager.record_task_metadata = true
  end

  def teardown
    Rake::TaskManager.record_task_metadata = false
    super
  end

  def test_no_args_given
    t = tasc :t
    assert_equal [], t.arg_names
    assert_equal({}, t.config)
  end

  def test_args_given
    t = tasc :t, :a, :b
    assert_equal [:a, :b], t.arg_names
    assert_equal({}, t.config)
  end

  def test_configs_given
    t = tasc :t, [:one, 'one'], [:two, 'two']
    assert_equal [], t.arg_names
    assert_equal({:one => 'one', :two => 'two'}, t.config)
  end

  def test_configs_are_parsed_from_a_string
    t = tasc :t, %{
      -o,--one [ONE]  : One doc
      --two [TWO]     : Two doc
      -t [THREE]      : Three doc
    }
    assert_equal [], t.arg_names
    assert_equal({
      :one => 'ONE', 
      :two => 'TWO',
      :t => 'THREE'
    }, t.config)
    
    assert_equal %q{
Usage: rake -- t [options] 
    -o, --one [ONE]                  One doc
        --two [TWO]                  Two doc
    -t [THREE]                       Three doc
    -h, --help                       Display this help message.
}, "\n" + t.parser.to_s
  end

  def test_args_and_configs_given
    t = tasc :t, :a, :b, [:one, 'one'], [:two, 'two']
    assert_equal [:a, :b], t.arg_names
    assert_equal({:one => 'one', :two => 'two'}, t.config)
  end

  def test_name_and_needs
    t = tasc(:t => [:pre])
    assert_equal "t", t.name
    assert_equal [], t.arg_names
    assert_equal({}, t.config)
    assert_equal ["pre"], t.prerequisites
  end

  def test_name_and_explicit_needs
    t = tasc(:t, :needs => [:pre])
    assert_equal "t", t.name
    assert_equal [], t.arg_names
    assert_equal({}, t.config)
    assert_equal ["pre"], t.prerequisites
  end

  def test_name_args_and_explicit_needs
    t = tasc(:t, :x, :y, :needs => [:pre])
    assert_equal "t", t.name
    assert_equal [:x, :y], t.arg_names
    assert_equal({}, t.config)
    assert_equal ["pre"], t.prerequisites
  end

  def test_name_configs_and_explicit_needs
    t = tasc(:t, [:one, 'one'], [:two, 'two'], :needs => [:pre])
    assert_equal "t", t.name
    assert_equal [], t.arg_names
    assert_equal({:one => 'one', :two => 'two'}, t.config)
    assert_equal ["pre"], t.prerequisites
  end

  def test_name_args_configs_and_explicit_needs
    t = tasc(:t, :x, :y, [:one, 'one'], [:two, 'two'], :needs => [:pre])
    assert_equal "t", t.name
    assert_equal [:x, :y], t.arg_names
    assert_equal({:one => 'one', :two => 'two'}, t.config)
    assert_equal ["pre"], t.prerequisites
  end

  def test_tasc_can_access_arguments_and_configs
    t = tasc(:t, :a, :b,
      [:one, 'one'], 
      [:two, 'two']
    ) do |tt, args|
      assert_equal({:one => 'ONE', :two => 'two'}, t.config)
      assert_equal 'ONE', tt[:one]
      assert_equal 'two', tt[:two]
      assert_equal 'ONE', t.one
      assert_equal 'two', t.two

      assert_equal({:a => 1, :b => 2}, args.to_hash)
      assert_equal 1, args[:a]
      assert_equal 2, args[:b]
      assert_equal 1, args.a
      assert_equal 2, args.b
    end
    t.invoke(1, '--one', 'ONE', 2)
  end

  def test_tasc_treads_single_letter_keys_as_shorts
    t = tasc :t, [:k, 'value']
    t.invoke('-k', 'VALUE')
    assert_equal 'VALUE', t.k
  end

  def test_tasc_handles_integers
    t = tasc :t, [:key, 1]
    t.invoke('--key', '8')
    assert_equal 8, t.key
  end

  def test_tasc_hanldes_floats
    t = tasc :t, [:key, 1.1]
    t.invoke('--key', '8.8')
    assert_equal 8.8, t.key
  end

  def test_tasc_handles_flags
    t = tasc :t, [:key, false]
    t.invoke('--key')
    assert_equal true, t.key
  end

  def test_tasc_handles_switches
    t = tasc :t, [:key, true]
    t.invoke('--key')
    assert_equal true, t.key

    t = tasc :t, [:key, true]
    t.invoke('--no-key')
    assert_equal false, t.key
  end

  def test_tasc_can_handle_optparse_patterns
    t = tasc :t, [:key, [], "--key x,y,z", Array]
    t.invoke('--key', 'a,b')
    assert_equal ['a', 'b'], t.key
  end

  def test_tasc_gueses_string_configs
    t = tasc :t, '--key [vaLue]'
    assert_equal 'vaLue', t.key
    t.invoke('--key', '8')
    assert_equal '8', t.key
  end

  def test_tasc_allows_empty_string_defaults
    t = tasc :t, '--key []'
    assert_equal '', t.key
  end

  def test_tasc_gueses_integer_configs
    t = tasc :t, '--key [1]'
    assert_equal 1, t.key
    t.invoke('--key', '8')
    assert_equal 8, t.key
  end

  def test_tasc_gueses_float_configs
    t = tasc :t, '--key [1.1]'
    assert_equal 1.1, t.key
    t.invoke('--key', '8.8')
    assert_equal 8.8, t.key
  end

  def test_tasc_gueses_flags
    t = tasc :t, '--key'
    assert_equal false, t.key
    t.invoke('--key')
    assert_equal true, t.key
  end

  def test_tasc_gueses_switches
    t = tasc :t, '--[no-]key'
    assert_equal true, t.key
    t.invoke('--no-key')
    assert_equal false, t.key
  end
end
