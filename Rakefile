#!/usr/bin/ruby
# -*- ruby -*-
# -*- coding: utf-8 -*-
$:.unshift(File.dirname(__FILE__)+'/lib/')
require 'rubygems'
require 'hoe'
require './lib/rinruby'

Hoe.plugin :git

Hoe.spec 'rinruby' do
  self.testlib=:rspec
  self.version=RinRuby::VERSION
  # self.rubyforge_name = 'rinruby' # if different than 'rinruby2'
  self.developer('David Dahl', 'rinruby_AT_ddahl.org')
  self.developer('Claudio Bustos', 'clbustos_AT_gmail.com')
  self.urls = ["http://rinruby.ddahl.org/"]
end

# vim: syntax=ruby
