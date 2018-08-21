require 'simplecov'
unless ENV['NO_COV']
  SimpleCov.start do
    add_filter '/spec/'
  end
end

$LOAD_PATH.unshift(File.expand_path(File.dirname(__FILE__)))
$LOAD_PATH.unshift(File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib')))
require 'rspec'
require 'matrix'
require 'complex'

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = [:should, :expect]
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


