source 'https://rubygems.org'

# Specify your gem's dependencies in rootapp-rinruby.gemspec
gemspec

gem 'rake', '~> 10.5.0' if RUBY_VERSION < '1.9.3'
gem 'rake' if RUBY_VERSION >= '1.9.3'

group :test do
  gem "codeclimate-test-reporter", require: nil
end
