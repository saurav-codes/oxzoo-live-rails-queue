ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Sets ENV for the block and restores it after.
    def with_env(values)
      saved = values.keys.to_h { |k| [k, ENV[k]] }
      values.each { |k, v| ENV[k] = v }
      yield
    ensure
      saved.each { |k, v| ENV[k] = v }
    end
  end
end
