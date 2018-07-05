#=RinRuby: Accessing the R[http://www.r-project.org] interpreter from pure Ruby
#
#RinRuby is a Ruby library that integrates the R interpreter in Ruby, making R's statistical routines and graphics available within Ruby.  The library consists of a single Ruby script that is simple to install and does not require any special compilation or installation of R.  Since the library is 100% pure Ruby, it works on a variety of operating systems, Ruby implementations, and versions of R.  RinRuby's methods are simple, making for readable code.  The {website [rinruby.ddahl.org]}[http://rinruby.ddahl.org] describes RinRuby usage, provides comprehensive documentation, gives several examples, and discusses RinRuby's implementation.
#

if defined?(R)
  require 'rinruby'
else
  R = :dummy
  require 'rinruby'
  Object::send(:remove_const, :R)
end

class RinRubyWithoutRConstant < RinRuby
  DEFAULT_PORT_NUMBER = 38542
  def initialize(*args)
    if args.size == 1 and args[0].kind_of?(Hash) then
      args[0][:port_number] ||= DEFAULT_PORT_NUMBER
    else
      args[3] ||= DEFAULT_PORT_NUMBER
    end
    super(*args)
  end
end
