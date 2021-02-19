#!/usr/bin/ruby
# -*- ruby -*-
# -*- coding: utf-8 -*-
require 'rubygems'
require_relative 'lib/rinruby'
begin 
require 'rspec'
require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec)
rescue LoadError
end

require 'bundler'

Bundler::GemHelper.install_tasks


# vim: syntax=ruby
