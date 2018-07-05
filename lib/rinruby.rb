#=RinRuby: Accessing the R[http://www.r-project.org] interpreter from pure Ruby
#
#RinRuby is a Ruby library that integrates the R interpreter in Ruby, making R's statistical routines and graphics available within Ruby.  The library consists of a single Ruby script that is simple to install and does not require any special compilation or installation of R.  Since the library is 100% pure Ruby, it works on a variety of operating systems, Ruby implementations, and versions of R.  RinRuby's methods are simple, making for readable code.  The {website [rinruby.ddahl.org]}[http://rinruby.ddahl.org] describes RinRuby usage, provides comprehensive documentation, gives several examples, and discusses RinRuby's implementation.
#
#Below is a simple example of RinRuby usage for simple linear regression. The simulation parameters are defined in Ruby, computations are performed in R, and Ruby reports the results. In a more elaborate application, the simulation parameter might come from input from a graphical user interface, the statistical analysis might be more involved, and the results might be an HTML page or PDF report.
#
#<b>Code</b>:
#
#      require "rinruby"
#      n = 10
#      beta_0 = 1
#      beta_1 = 0.25
#      alpha = 0.05
#      seed = 23423
#      R.x = (1..n).entries
#      R.eval <<EOF
#          set.seed(#{seed})
#          y <- #{beta_0} + #{beta_1}*x + rnorm(#{n})
#          fit <- lm( y ~ x )
#          est <- round(coef(fit),3)
#          pvalue <- summary(fit)$coefficients[2,4]
#      EOF
#      puts "E(y|x) ~= #{R.est[0]} + #{R.est[1]} * x"
#      if R.pvalue < alpha
#        puts "Reject the null hypothesis and conclude that x and y are related."
#      else
#        puts "There is insufficient evidence to conclude that x and y are related."
#      end
#
#<b>Output</b>:
#
#      E(y|x) ~= 1.264 + 0.273 * x
#      Reject the null hypothesis and conclude that x and y are related.
#
#Coded by:: David B. Dahl
#Documented by:: David B. Dahl & Scott Crawford
#Maintained by:: Claudio Bustos
#Copyright:: 2005-2009
#Web page:: http://rinruby.ddahl.org
#E-mail::   mailto:rinruby@ddahl.org
#License::  GNU Lesser General Public License (LGPL), version 3 or later
#
#--
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>
#++
#
#
#The files "java" and "readline" are used when available to add functionality.
require 'matrix'
class RinRuby

  require 'socket'

  VERSION = '2.0.3'

  attr_reader :interactive
  attr_reader :readline
  # Exception for closed engine
  EngineClosed=Class.new(Exception)
  # Parse error
  ParseError=Class.new(Exception)


#RinRuby is invoked within a Ruby script (or the interactive "irb" prompt denoted >>) using:
#
#      >> require "rinruby"
#
#The previous statement reads the definition of the RinRuby class into the current Ruby interpreter and creates an instance of the RinRuby class named R. There is a second method for starting an instance of R which allows the user to use any name for the instance, in this case myr:
#
#      >> require "rinruby"
#      >> myr = RinRuby.new
#      >> myr.eval "rnorm(1)"
#
#Any number of independent instances of R can be created in this way.
#
#<b>Parameters that can be passed to the new method using a Hash:</b>
#
#* :echo: By setting the echo to false, output from R is suppressed, although warnings are still printed. This option can be changed later by using the echo method. The default is true.
#* :interactive: When interactive is false, R is run in non-interactive mode, resulting in plots without an explicit device being written to Rplots.pdf. Otherwise (i.e., interactive is true), plots are shown on the screen. The default is true.
#* :executable: The path of the R executable (which is "R" in Linux and Mac OS X, or "Rterm.exe" in Windows) can be set with the executable argument. The default is nil which makes RinRuby use the registry keys to find the path (on Windows) or use the path defined by $PATH (on Linux and Mac OS X).
#* :port_number: This is the smallest port number on the local host that could be used to pass data between Ruby and R. The actual port number used depends on port_width.
#* :port_width: RinRuby will randomly select a uniform number between port_number and port_number + port_width - 1 (inclusive) to pass data between Ruby and R. If the randomly selected port is not available, RinRuby will continue selecting random ports until it finds one that is available. By setting port_width to 1, RinRuby will wait until port_number is available. The default port_width is 1000.
#
#It may be desirable to change the parameters to the instance of R, but still call it by the name of R. In that case the old instance of R which was created with the 'require "rinruby"' statement should be closed first using the quit method which is explained below. Unless the previous instance is killed, it will continue to use system resources until exiting Ruby. The following shows an example by changing the parameter echo:
#
#      >> require "rinruby"
#      >> R.quit
#      >> R = RinRuby.new(false)
attr_accessor :echo_enabled
attr_reader :executable
attr_reader :port_number
attr_reader :port_width
attr_reader :hostname
def initialize(*args)
  opts=Hash.new
  if args.size==1 and args[0].is_a? Hash
    opts=args[0]
  else
    opts[:echo]=args.shift unless args.size==0
    opts[:interactive]=args.shift unless args.size==0
    opts[:executable]=args.shift unless args.size==0
    opts[:port_number]=args.shift unless args.size==0
    opts[:port_width]=args.shift unless args.size==0
  end
  default_opts= {:echo=>true, :interactive=>true, :executable=>nil, :port_number=>38442, :port_width=>1000, :hostname=>'127.0.0.1'}

    @opts=default_opts.merge(opts)
    @port_width=@opts[:port_width]
    @executable=@opts[:executable]
    @hostname=@opts[:hostname]
    while true
      begin
        @port_number = @opts[:port_number] + rand(port_width)
        @server_socket = TCPServer::new(@hostname, @port_number)
        break
      rescue Errno::EADDRINUSE
        sleep 0.5 if port_width == 1
      end
    end
    @echo_enabled = @opts[:echo]
    @echo_stderr = false
    @interactive = @opts[:interactive]
    @platform = case RUBY_PLATFORM
      when /mswin/ then 'windows'
      when /mingw/ then 'windows'
      when /bccwin/ then 'windows'
      when /cygwin/ then 'windows-cygwin'
      when /java/
        require 'java' #:nodoc:
        if java.lang.System.getProperty("os.name") =~ /[Ww]indows/
          'windows-java'
        else
          'default-java'
        end
      else 'default'
    end
    if @executable == nil
      @executable = ( @platform =~ /windows/ ) ? find_R_on_windows(@platform =~ /cygwin/) : 'R'
    end
    platform_options = []
    if ( @interactive )
      begin
        require 'readline'
      rescue LoadError
      end
      @readline = defined?(Readline)
      platform_options << ( ( @platform =~ /windows/ ) ? '--ess' : '--interactive' )
    else
      @readline = false
    end
    cmd = %Q<#{executable} #{platform_options.join(' ')} --slave>
    @engine = IO.popen(cmd,"w+")
    @reader = @engine
    @writer = @engine
    raise "Engine closed" if @engine.closed?
    @writer.puts <<-EOF
      #{RinRuby_KeepTrying_Variable} <- TRUE
      while ( #{RinRuby_KeepTrying_Variable} ) {
        #{RinRuby_Socket} <- try(suppressWarnings(socketConnection("#{@hostname}", #{@port_number}, blocking=TRUE, open="rb")),TRUE)
        setTCPNoDelay(#{RinRuby_Socket}, value=TRUE)
        if ( inherits(#{RinRuby_Socket},"try-error") ) {
          Sys.sleep(0.1)
        } else {
          #{RinRuby_KeepTrying_Variable} <- FALSE
        }
      }
      rm(#{RinRuby_KeepTrying_Variable})
    EOF
    r_rinruby_get_value
    r_rinruby_pull
    r_rinruby_parseable
    @socket = @server_socket.accept
    @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
    echo(nil,true) if @platform =~ /.*-java/      # Redirect error messages on the Java platform
  end

#The quit method will properly close the bridge between Ruby and R, freeing up system resources. This method does not need to be run when a Ruby script ends.

  def quit
    begin
      @writer.puts "q(save='no')"
      # TODO: Verify if read is needed
      @socket.read()
      #@socket.close
      @engine.close


      @server_socket.close
      #@reader.close
      #@writer.close
      true
    ensure
      @engine.close unless @engine.closed?
      @server_socket.close unless @server_socket.closed?
    end
  end


#The eval instance method passes the R commands contained in the supplied string and displays any resulting plots or prints the output. For example:
#
#      >>  sample_size = 10
#      >>  R.eval "x <- rnorm(#{sample_size})"
#      >>  R.eval "summary(x)"
#      >>  R.eval "sd(x)"
#
#produces the following:
#
#         Min. 1st Qu.        Median      Mean 3rd Qu.         Max.
#      -1.88900 -0.84930 -0.45220 -0.49290 -0.06069          0.78160
#      [1] 0.7327981
#
#This example used a string substitution to make the argument to first eval method equivalent to x <- rnorm(10). This example used three invocations of the eval method, but a single invoke is possible using a here document:
#
#      >> R.eval <<EOF
#              x <- rnorm(#{sample_size})
#              summary(x)
#              sd(x)
#         EOF
#
#<b>Parameters that can be passed to the eval method</b>
#
#* string: The string parameter is the code which is to be passed to R, for example, string = "hist(gamma(1000,5,3))". The string can also span several lines of code by use of a here document, as shown:
#      R.eval <<EOF
#         x<-rgamma(1000,5,3)
#         hist(x)
#      EOF
#
#* echo_override: This argument allows one to set the echo behavior for this call only. The default for echo_override is nil, which does not override the current echo behavior.

  def eval(string, echo_override=nil)
    raise EngineClosed if @engine.closed?
    echo_enabled = ( echo_override != nil ) ? echo_override : @echo_enabled
    if complete?(string)
      @writer.puts string
      @writer.puts "warning('#{RinRuby_Stderr_Flag}',immediate.=TRUE)" if @echo_stderr
      @writer.puts "print('#{RinRuby_Eval_Flag}')"
    else
      raise ParseError, "Parse error on eval:#{string}"
    end
    Signal.trap('INT') do
      @writer.print ''
      @reader.gets if @platform !~ /java/
      Signal.trap('INT') do
      end
      return true
    end
    found_eval_flag = false
    found_stderr_flag = false
    while true
      echo_eligible = true
      begin
        line = @reader.gets
      rescue
        return false
      end
      if ! line
        return false
      end
      while line.chomp!
      end
      line = line[8..-1] if line[0] == 27     # Delete escape sequence
      if line == "[1] \"#{RinRuby_Eval_Flag}\""
        found_eval_flag = true
        echo_eligible = false
      end
      if line == "Warning: #{RinRuby_Stderr_Flag}"
        found_stderr_flag = true
        echo_eligible = false
      end
      break if found_eval_flag && ( found_stderr_flag == @echo_stderr )
      return false if line == RinRuby_Exit_Flag
      if echo_enabled && echo_eligible
        puts line
        $stdout.flush if @platform !~ /windows/
      end
    end
    Signal.trap('INT') do
    end
    true
  end

#When sending code to Ruby using an interactive prompt, this method will change the prompt to an R prompt. From the R prompt commands can be sent to R exactly as if the R program was actually running. When the user is ready to return to Ruby, then the command exit() will return the prompt to Ruby. This is the ideal situation for the explorative programmer who needs to run several lines of code in R, and see the results after each command. This is also an easy way to execute loops without the use of a here document. It should be noted that the prompt command does not work in a script, just Ruby's interactive irb.
#
#<b>Parameters that can be passed to the prompt method:</b>
#
#* regular_prompt: This defines the string used to denote the R prompt.
#
#* continue_prompt: This is the string used to denote R's prompt for an incomplete statement (such as a multiple for loop).

  def prompt(regular_prompt="> ", continue_prompt="+ ")
    raise "The 'prompt' method only available in 'interactive' mode" if ! @interactive
    return false if ! eval("0",false)
    prompt = regular_prompt
    while true
      cmds = []
      while true
        if @readline && @interactive
          cmd = Readline.readline(prompt,true)
        else
          print prompt
          $stdout.flush
          cmd = gets.strip
        end
        cmds << cmd
        begin
          if complete?(cmds.join("\n"))
            prompt = regular_prompt
            break
          else
            prompt = continue_prompt
          end
        rescue
          puts "Parse error"
          prompt = regular_prompt
          cmds = []
          break
        end
      end
      next if cmds.length == 0
      break if cmds.length == 1 && cmds[0] == "exit()"
      break if ! eval(cmds.join("\n"),true)
    end
    true
  end

#If a method is called which is not defined, then it is assumed that the user is attempting to either pull or assign a variable to R.  This allows for the short-hand equivalents to the pull and assign methods.  For example:
#
#      >> R.x = 2
#
#is the same as:
#
#      >> R.assign("x",2)
#
#Also:
#
#      >> n = R.x
#
#is the same as:
#
#      >> n = R.pull("x")
#
#The parameters passed to method_missing are those used for the pull or assign depending on the context.

  def method_missing(symbol, *args)
    name = symbol.id2name
    if name =~ /(.*)=$/
      raise ArgumentError, "You shouldn't assign nil" if args==[nil]
      super if args.length != 1
      assign($1,args[0])
    else
      super if args.length != 0
      pull(name)
    end
  end

#Data is copied from Ruby to R using the assign method or a short-hand equivalent. For example:
#
#      >> names = ["Lisa","Teasha","Aaron","Thomas"]
#      >> R.assign "people", names
#      >> R.eval "sort(people)"
#
#produces the following :
#
#      [1] "Aaron"     "Lisa"     "Teasha" "Thomas"
#
#The short-hand equivalent to the assign method is simply:
#
#      >> R.people = names
#
#Some care is needed when using the short-hand of the assign method since the label (i.e., people in this case) must be a valid method name in Ruby. For example, R.copy.of.names = names will not work, but R.copy_of_names = names is permissible.
#
#The assign method supports Ruby variables of type Fixnum (i.e., integer), Bignum (i.e., integer), Float (i.e., double), String, and arrays of one of those three fundamental types. Note that Fixnum or Bignum values that exceed the capacity of R's integers are silently converted to doubles.  Data in other formats must be coerced when copying to R.
#
#<b>Parameters that can be passed to the assign method:</b>
#
#* name: The name of the variable desired in R.
#
#* value: The value the R variable should have. The assign method supports Ruby variables of type Fixnum (i.e., integer), Bignum (i.e., integer), Float (i.e., double), String, and arrays of one of those three fundamental types.  Note that Fixnum or Bignum values that exceed the capacity of R's integers are silently converted to doubles.  Data in other formats must be coerced when copying to R.
#
#The assign method is an alternative to the simplified method, with some additional flexibility. When using the simplified method, the parameters of name and value are automatically used, in other words:
#
#      >> R.test = 144
#
#is the same as:
#
#      >> R.assign("test",144)
#
#Of course it would be confusing to use the shorthand notation to assign a variable named eval, echo, or any other already defined function. RinRuby would assume you were calling the function, rather than trying to assign a variable.
#
#When assigning an array containing differing types of variables, RinRuby will follow R’s conversion conventions. An array that contains any Strings will result in a character vector in R. If the array does not contain any Strings, but it does contain a Float or a large integer (in absolute value), then the result will be a numeric vector of Doubles in R. If there are only integers that are suffciently small (in absolute value), then the result will be a numeric vector of integers in R.

  def assign(name, value)
     raise EngineClosed if @engine.closed?
    if assignable?(name)
      assign_engine(name,value)
    else
      raise ParseError, "Parse error"
    end
  end

#Data is copied from R to Ruby using the pull method or a short-hand equivalent. The R object x defined with an eval method can be copied to Ruby object copy_of_x as follows:
#
#      >> R.eval "x <- rnorm(10)"
#      >> copy_of_x = R.pull "x"
#      >> puts copy_of_x
#
#which produces the following :
#
#      -0.376404489256671
#      -1.0759798269397
#      -0.494240140140996
#      0.131171385795721
#      -0.878328334369391
#      -0.762290423047929
#      -0.410227216105828
#      0.0445512804225151
#      -1.88887454545995
#      0.781602719849499
#
#RinRuby also supports a convenient short-hand notation when the argument to pull is simply a previously-defined R object (whose name conforms to Ruby's requirements for method names). For example:
#
#      >> copy_of_x = R.x
#
#The explicit assign method, however, can take an arbitrary R statement. For example:
#
#      >> summary_of_x = R.pull "as.numeric(summary(x))"
#      >> puts summary_of_x
#
#produces the following:
#
#      -1.889
#      -0.8493
#      -0.4522
#      -0.4929
#      -0.06069
#      0.7816
#
#Notice the use above of the as.numeric function in R. This is necessary since the pull method only supports R vectors which are numeric (i.e., integers or doubles) and character (i.e., strings). Data in other formats must be coerced when copying to Ruby.
#
#<b>Parameters that can be passed to the pull method:</b>
#
#* string: The name of the variable that should be pulled from R. The pull method only supports R vectors which are numeric (i.e., integers or doubles) or character (i.e., strings). The R value of NA is pulled as nil into Ruby. Data in other formats must be coerced when copying to Ruby.
#
#* singletons: R represents a single number as a vector of length one, but in Ruby it is often more convenient to use a number rather than an array of length one. Setting singleton=false will cause the pull method to shed the array, while singletons=true will return the number of string within an array.  The default is false.
#
#The pull method is an alternative to the simplified form where the parameters are automatically used.  For example:
#
#      >> puts R.test
#
#is the same as:
#
#      >> puts R.pull("test")

  def pull(string, singletons=false)
    raise EngineClosed if @engine.closed?
    if complete?(string)
      result = pull_engine(string)
      if ( ! singletons ) && ( result.length == 1 ) && ( result.class != String )
        result = result[0]
      end
      result
    else
      raise ParseError, "Parse error"
    end
  end

#The echo method controls whether the eval method displays output from R and, if echo is enabled, whether messages, warnings, and errors from stderr are also displayed.
#
#<b>Parameters that can be passed to the eval method</b>
#
#* enable: Setting enable to false will turn all output off until the echo command is used again with enable equal to true. The default is nil, which will return the current setting.
#
#* stderr: Setting stderr to true will force messages, warnings, and errors from R to be routed through stdout.  Using stderr redirection is typically not needed for the C implementation of Ruby and is thus not not enabled by default for this implementation.  It is typically necessary for jRuby and is enabled by default in this case.  This redirection works well in practice but it can lead to interleaving output which may confuse RinRuby.  In such cases, stderr redirection should not be used.  Echoing must be enabled when using stderr redirection.

  def echo(enable=nil,stderr=nil)
    if ( enable == false ) && ( stderr == true )
      raise "You can only redirect stderr if you are echoing is enabled."
    end
    if ( enable != nil ) && ( enable != @echo_enabled )
      echo(nil,false) if ! enable
      @echo_enabled = ! @echo_enabled
    end
    if @echo_enabled && ( stderr != nil ) && ( stderr != @echo_stderr )
      @echo_stderr = ! @echo_stderr
      if @echo_stderr
        eval "sink(stdout(),type='message')"
      else
        eval "sink(type='message')"
      end
    end
    [ @echo_enabled, @echo_stderr ]
  end

  private

  #:stopdoc:
  RinRuby_Type_NotFound = -2
  RinRuby_Type_Unknown = -1
  RinRuby_Type_Double = 0
  RinRuby_Type_Integer = 1
  RinRuby_Type_String = 2
  RinRuby_Type_String_Array = 3
  RinRuby_Type_Matrix = 4

  RinRuby_KeepTrying_Variable = ".RINRUBY.KEEPTRYING.VARIABLE"
  RinRuby_Length_Variable = ".RINRUBY.PULL.LENGTH.VARIABLE"
  RinRuby_Type_Variable = ".RINRUBY.PULL.TYPE.VARIABLE"
  RinRuby_Socket = ".RINRUBY.PULL.SOCKET"
  RinRuby_Variable = ".RINRUBY.PULL.VARIABLE"
  RinRuby_Parse_String = ".RINRUBY.PARSE.STRING"
  RinRuby_Eval_Flag = "RINRUBY.EVAL.FLAG"
  RinRuby_Stderr_Flag = "RINRUBY.STDERR.FLAG"
  RinRuby_Exit_Flag = "RINRUBY.EXIT.FLAG"
  RinRuby_Max_Unsigned_Integer = 2**32
  RinRuby_Half_Max_Unsigned_Integer = 2**31
  RinRuby_NA_R_Integer = 2**31
  RinRuby_Max_R_Integer = 2**31-1
  RinRuby_Min_R_Integer = -2**31+1
  #:startdoc:


  def r_rinruby_parseable
    @writer.puts <<-EOF
    rinruby_parseable<-function(var) {
      result=try(parse(text=var),TRUE)
      if(inherits(result, "try-error")) {
        writeBin(as.integer(-1),#{RinRuby_Socket}, endian="big")
      } else {
        writeBin(as.integer(1),#{RinRuby_Socket}, endian="big")
      }
    }
    EOF
  end
  # Create function on ruby to get values
  def r_rinruby_get_value
    @writer.puts <<-EOF
    rinruby_get_value <-function() {
      value <- NULL
      type <- readBin(#{RinRuby_Socket}, integer(), 1, endian="big")
      length <- readBin(#{RinRuby_Socket},integer(),1,endian="big")
      if ( type == #{RinRuby_Type_Double} ) {
        value <- readBin(#{RinRuby_Socket},numeric(), length,endian="big")
        } else if ( type == #{RinRuby_Type_Integer} ) {
        value <- readBin(#{RinRuby_Socket},integer(), length, endian="big")
        } else if ( type == #{RinRuby_Type_String} ) {
        value <- readBin(#{RinRuby_Socket},character(),1,endian="big")
        } else {
          value <-NULL
        }
      value
      }
    EOF
  end

  def r_rinruby_pull
 @writer.puts <<-EOF
 rinruby_pull <-function(var)
{
  if ( inherits(var ,"try-error") ) {
     writeBin(as.integer(#{RinRuby_Type_NotFound}),#{RinRuby_Socket},endian="big")
  } else {
    if (is.matrix(var)) {
      writeBin(as.integer(#{RinRuby_Type_Matrix}),#{RinRuby_Socket},endian="big")
      writeBin(as.integer(dim(var)[1]),#{RinRuby_Socket},endian="big")
      writeBin(as.integer(dim(var)[2]),#{RinRuby_Socket},endian="big")

    }  else if ( is.double(var) ) {
      writeBin(as.integer(#{RinRuby_Type_Double}),#{RinRuby_Socket},endian="big")
      writeBin(as.integer(length(var)),#{RinRuby_Socket},endian="big")
      writeBin(var,#{RinRuby_Socket},endian="big")
    } else if ( is.integer(var) ) {
      writeBin(as.integer(#{RinRuby_Type_Integer}),#{RinRuby_Socket},endian="big")
      writeBin(as.integer(length(var)),#{RinRuby_Socket},endian="big")
      writeBin(var,#{RinRuby_Socket},endian="big")
    } else if ( is.character(var) && ( length(var) == 1 ) ) {
      writeBin(as.integer(#{RinRuby_Type_String}),#{RinRuby_Socket},endian="big")
      writeBin(as.integer(nchar(var)),#{RinRuby_Socket},endian="big")
      writeBin(var,#{RinRuby_Socket},endian="big")
    } else if ( is.character(var) && ( length(var) > 1 ) ) {
      writeBin(as.integer(#{RinRuby_Type_String_Array}),#{RinRuby_Socket},endian="big")
      writeBin(as.integer(length(var)),#{RinRuby_Socket},endian="big")
    } else {
      writeBin(as.integer(#{RinRuby_Type_Unknown}),#{RinRuby_Socket},endian="big")
    }
  }
}
    EOF


  end
  def to_signed_int(y)
    if y.kind_of?(Integer)
      ( y > RinRuby_Half_Max_Unsigned_Integer ) ? -(RinRuby_Max_Unsigned_Integer-y) : ( y == RinRuby_NA_R_Integer ? nil : y )
    else
      y.collect { |x| ( x > RinRuby_Half_Max_Unsigned_Integer ) ? -(RinRuby_Max_Unsigned_Integer-x) : ( x == RinRuby_NA_R_Integer ? nil : x ) }
    end
  end

  def assign_engine(name, value)
    original_value = value
    # Special assign for matrixes
    if value.kind_of?(::Matrix)
      values=value.row_size.times.collect {|i| value.column_size.times.collect {|j| value[i,j]}}.flatten
      eval "#{name}=matrix(c(#{values.join(',')}), #{value.row_size}, #{value.column_size}, TRUE)"
      return original_value
    end

    if value.kind_of?(String)
      type = RinRuby_Type_String
      length = 1
    elsif value.kind_of?(Integer)
      if ( value >= RinRuby_Min_R_Integer ) && ( value <= RinRuby_Max_R_Integer )
        value = [ value.to_i ]
        type = RinRuby_Type_Integer
      else
        value = [ value.to_f ]
        type = RinRuby_Type_Double
      end
      length = 1
    elsif value.kind_of?(Float)
      value = [ value.to_f ]
      type = RinRuby_Type_Double
      length = 1
    elsif value.kind_of?(Array)
      begin
        if value.any? { |x| x.kind_of?(String) }
          eval "#{name} <- character(#{value.length})"
          for index in 0...value.length
            assign_engine("#{name}[#{index}+1]",value[index])
          end
          return original_value
        elsif value.any? { |x| x.kind_of?(Float) }
          type = RinRuby_Type_Double
          value = value.collect { |x| x.to_f }
        elsif value.all? { |x| x.kind_of?(Integer) }
          if value.all? { |x| ( x >= RinRuby_Min_R_Integer ) && ( x <= RinRuby_Max_R_Integer ) }
            type = RinRuby_Type_Integer
          else
            value = value.collect { |x| x.to_f }
            type = RinRuby_Type_Double
          end
        else
          raise "Unsupported data type on Ruby's end"
        end
      rescue
        raise "Unsupported data type on Ruby's end"
      end
      length = value.length
    else
      raise "Unsupported data type on Ruby's end"
    end
    @writer.puts "#{name} <- rinruby_get_value()"

    @socket.write([type,length].pack('NN'))
    if ( type == RinRuby_Type_String )
      @socket.write(value)
      @socket.write([0].pack('C'))   # zero-terminated strings
    else
      @socket.write(value.pack( ( type==RinRuby_Type_Double ? 'G' : 'N' )*length ))
    end
    original_value
  end

  def pull_engine(string)
    @writer.puts <<-EOF
      rinruby_pull(try(#{string}))
    EOF

    buffer = ""
    @socket.read(4,buffer)
    type = to_signed_int(buffer.unpack('N')[0].to_i)
    if ( type == RinRuby_Type_Unknown )
      raise "Unsupported data type on R's end"
    end
    if ( type == RinRuby_Type_NotFound )
      return nil
    end
    @socket.read(4,buffer)
    length = to_signed_int(buffer.unpack('N')[0].to_i)

    if ( type == RinRuby_Type_Double )
      @socket.read(8*length,buffer)
      result = buffer.unpack('G'*length)
    elsif ( type == RinRuby_Type_Integer )
      @socket.read(4*length,buffer)
      result = to_signed_int(buffer.unpack('N'*length))
    elsif ( type == RinRuby_Type_String )
      @socket.read(length,buffer)
      result = buffer.dup
      @socket.read(1,buffer)    # zero-terminated string
      result
    elsif ( type == RinRuby_Type_String_Array )
      result = Array.new(length,'')
      for index in 0...length
        result[index] = pull "#{string}[#{index+1}]"
      end
    elsif (type == RinRuby_Type_Matrix)
      rows=length
      @socket.read(4,buffer)
      cols = to_signed_int(buffer.unpack('N')[0].to_i)
      elements=pull "as.vector(#{string})"
      index=0
      result=Matrix.rows(rows.times.collect {|i|
        cols.times.collect {|j|
          elements[(j*rows)+i]
        }
      })
      def result.length; 2;end
    else
      raise "Unsupported data type on Ruby's end"
    end
    result
  end

  def complete?(string)
    assign_engine(RinRuby_Parse_String, string)
    @writer.puts "rinruby_parseable(#{RinRuby_Parse_String})"
    buffer=""
    @socket.read(4,buffer)
    @writer.puts "rm(#{RinRuby_Parse_String})"
    result = to_signed_int(buffer.unpack('N')[0].to_i)
    return result==-1 ? false : true

=begin

    result = pull_engine("unlist(lapply(c('.*','^Error in parse.*','^Error in parse.*unexpected end of input.*'),
      grep,try({parse(text=#{RinRuby_Parse_String}); 1}, silent=TRUE)))")

    return true if result.length == 1
    return false if result.length == 3
    raise ParseError, "Parse error"
=end
  end
  public :complete?
  def assignable?(string)
    raise ParseError, "Parse error" if ! complete?(string)
    assign_engine(RinRuby_Parse_String,string)
    result = pull_engine("as.integer(ifelse(inherits(try({eval(parse(text=paste(#{RinRuby_Parse_String},'<- 1')))}, silent=TRUE),'try-error'),1,0))")
    @writer.puts "rm(#{RinRuby_Parse_String})"
    return true if result == [0]
    raise ParseError, "Parse error"
  end

  def find_R_on_windows(cygwin)
    path = '?'
    for root in [ 'HKEY_LOCAL_MACHINE', 'HKEY_CURRENT_USER' ]
      if cygwin then
        [:w, :W].collect{|opt| # [64bit, then 32bit registry]
          [:R64, :R].collect{|mode|
            `regtool list -#{opt} /#{root}/Software/R-core/#{mode} 2>/dev/null`.lines.collect{|v|
              v =~ /^\d\.\d\.\d/ ? $& : nil
            }.compact.sort{|a, b| # latest version has higher priority
              b <=> a
            }.collect{|ver|
              ["-#{opt}", "/#{root}/Software/R-core/#{mode}/#{ver}/InstallPath"]
            }
          }
        }.flatten(2).each{|args|
          v = `regtool get #{args.join(' ')}`.chomp
          unless v.empty? then
            path = v
            break
          end
        }
      else
        proc{|str| # Remove invalid byte sequence
          if RUBY_VERSION >= "2.1.0" then
            str.scrub
          elsif RUBY_VERSION >= "1.9.0" then
            str.chars.collect{|c| (c.valid_encoding?) ? c : '*'}.join
          else
            str
          end
        }.call(`reg query "#{root}\\Software\\R-core" /v "InstallPath" /s`).each_line do |line|
          next if line !~ /^\s+InstallPath\s+REG_SZ\s+(.*)/
          path = $1
          while path.chomp!
          end
          break
        end
      end
      break if path != '?'
    end
    if path == '?'
      # search at default install path
      path = [
        "Program Files",
        "Program Files (x86)"
      ].collect{|prog_dir|
        Dir::glob(File::join(
            cygwin ? "/cygdrive/c" : "C:",
            prog_dir, "R", "*"))
      }.flatten[0]
      raise "Cannot locate R executable" unless path
    end
    if cygwin
      path = `cygpath '#{path}'`
      while path.chomp!
      end
      path = [path.gsub(' ','\ '), path]
    else
      path = [path.gsub('\\','/')]
    end
    for hierarchy in [ 'bin', 'bin/x64', 'bin/i386']
      path.each{|item|
        target = "#{item}/#{hierarchy}/Rterm.exe"
        if File.exists? target
          return %Q<"#{target}">
        end
      }
    end
    raise "Cannot locate R executable"
  end

end

if ! defined?(R)
  #R is an instance of RinRuby.  If for some reason the user does not want R to be initialized (to save system resources), then create a default value for R (e.g., <b>R=2</b> ) in which case RinRuby will not overwrite the value of R.

  R = RinRuby.new
end

