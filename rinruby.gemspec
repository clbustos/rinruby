# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'version'

Gem::Specification.new do |spec|
  spec.name          = "rinruby"
  spec.version       = Rinruby::VERSION
  spec.authors       = ["David Dahl", "Scott Crawford", "Claudio Bustos"]
  spec.email         = ["rinruby@ddahl.org", "scott@ddahl.org", "clbustos@gmail.com"]
  spec.summary       = %q{RinRuby is a Ruby library that integrates the R interpreter in Ruby}
  spec.description   = %q{RinRuby is a Ruby library that integrates the R interpreter in Ruby, making R's statistical routines and graphics available within Ruby. The library consists of a single Ruby script that is simple to install and does not require any special compilation or installation of R. Since the library is 100% pure Ruby, it works on a variety of operating systems, Ruby implementations, and versions of R.  RinRuby's methods are simple, making for readable code.  The {website [rinruby.ddahl.org]}[http://rinruby.ddahl.org] describes RinRuby usage, provides comprehensive documentation, gives several examples, and discusses RinRuby's implementation.}
  spec.homepage      = "http://rinruby.ddahl.org"
  spec.license       = "Copyright 2005-2008 David B. Dahl"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", ">= 2.11"
  spec.add_development_dependency "hoe"
end
