require "codeclimate-test-reporter"
CodeClimate::TestReporter.start
$LOAD_PATH.unshift(File.expand_path(File.dirname(__FILE__)))
$LOAD_PATH.unshift(File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib')))
require 'rspec'
require 'rinruby'

require 'matrix'

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = [:expect]
  end

  # Use color in STDOUT
  config.color = true

  # Use color not only in STDOUT but also in pagers and files
  config.tty = true

  # Use the specified formatter
  config.formatter = :documentation # :progress, :html, :textmate
end


class String
  def deindent
    gsub /^[ \t]*/, ''
  end
end
