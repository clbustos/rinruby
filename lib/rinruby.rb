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

require File.expand_path(File.dirname(__FILE__) + '/rinruby/version.rb')

class RinRuby

  require 'socket'

  # Exception for closed engine
  EngineClosed=Class.new(RuntimeError)
  # Parse error
  ParseError=Class.new(RuntimeError)

  RinRuby_Env = ".RinRuby"
  RinRuby_Endian = ([1].pack("L").unpack("C*")[0] == 1) ? (:little) : (:big)

  attr_reader :interactive
  attr_reader :readline
  attr_reader :echo_enabled
  attr_reader :executable
  attr_reader :port_number
  attr_reader :port_width
  attr_reader :hostname
      
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
  def initialize(*args)
    @opts = {:echo=>true, :interactive=>true, :executable=>nil, 
        :port_number=>38442, :port_width=>1000, :hostname=>'127.0.0.1', :persistent => true}        
    if args.size==1 and args[0].is_a? Hash
      @opts.merge!(args[0])
    else
      [:echo, :interactive, :executable, :port_number, :port_width].zip(args).each{|k, v|
        @opts[k] = ((v == nil) ? @opts[k] : v)
      }
    end
    [:port_width, :executable, :hostname, :interactive, [:echo, :echo_enabled]].each{|k_src, k_dst|
      Kernel.eval("@#{k_dst || k_src} = @opts[:#{k_src}]", binding)
    }
    @echo_stderr = false

    raise Errno::EADDRINUSE unless (@port_number = 
        (@opts[:port_number]...(@opts[:port_number] + @opts[:port_width])).to_a.shuffle.find{|i|
      begin
        @server_socket = TCPServer::new(@hostname, i)
      rescue Errno::EADDRINUSE
        false
      end
    })
    
    @platform = case RUBY_PLATFORM
      when /mswin/, /mingw/, /bccwin/ then 'windows'
      when /cygwin/ then 'windows-cygwin'
      when /java/
        require 'java' #:nodoc:
        "#{java.lang.System.getProperty('os.name') =~ /[Ww]indows/ ? 'windows' : 'default'}-java"
      else 'default'
    end
    @executable ||= ( @platform =~ /windows/ ) ? self.class.find_R_on_windows(@platform =~ /cygwin/) : 'R'
    
    @platform_options = []
    if @interactive then
      if @executable =~ /Rterm\.exe["']?$/ then
        @platform_options += ['--ess']
      elsif @platform !~ /java$/ then
        # intentionally interactive off under java
        @platform_options += ['--no-readline', '--interactive']
      end
    end
    
    cmd = %Q<#{executable} #{@platform_options.join(' ')} --slave>
    cmd = (@platform =~ /^windows(?!-cygwin)/) ? "#{cmd} 2>NUL" : "exec #{cmd} 2>/dev/null"
    if @platform_options.include?('--interactive') then
      require 'pty'
      @reader, @writer, @r_pid = PTY::spawn("stty -echo && #{cmd}")
    else
      @writer = @reader = IO::popen(cmd, 'w+')
      @r_pid = @reader.pid
    end
    raise EngineClosed if (@reader.closed? || @writer.closed?)
    
    @writer.puts <<-EOF
      assign("#{RinRuby_Env}", new.env(), envir = globalenv())
    EOF
    @socket = nil
    [:socket_io, :assign, :pull, :check].each{|fname| self.send("r_rinruby_#{fname}")}
    @writer.flush
    
    @eval_count = 0
    eval("0", false) # cleanup @reader
    
    # JRuby on *NIX runs forcefully in non-interactive, where stop() halts R execution immediately in default.
    # To continue when R error occurs, an error handler is added as a workaround  
    # @see https://stat.ethz.ch/R-manual/R-devel/library/base/html/stop.html
    eval("options(error=dump.frames)") if @platform =~ /^(?!windows-).*java$/
  end

#The quit method will properly close the bridge between Ruby and R, freeing up system resources. This method does not need to be run when a Ruby script ends.

  def quit
    begin
      @writer.puts "q(save='no')"
      @writer.close
    rescue
    end
    @reader.close rescue nil
    @server_socket.close rescue nil
    true
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
#* b: echo block, which will be used as echo_override when echo_override equals to nil

  def eval(string, echo_override = nil, &b)
    echo_proc = case echo_override # echo on when echo_proc == nil
    when Proc
      echo_override
    when nil
      b || (@echo_enabled ? nil : proc{})
    else
      echo_override ? nil : proc{}
    end
    
    if_parseable(string){|fun|
      eval_engine("#{fun}()", &echo_proc)
    }
  end

#When sending code to Ruby using an interactive prompt, this method will change the prompt to an R prompt. From the R prompt commands can be sent to R exactly as if the R program was actually running. When the user is ready to return to Ruby, then the command exit() will return the prompt to Ruby. This is the ideal situation for the explorative programmer who needs to run several lines of code in R, and see the results after each command. This is also an easy way to execute loops without the use of a here document. It should be noted that the prompt command does not work in a script, just Ruby's interactive irb.
#
#<b>Parameters that can be passed to the prompt method:</b>
#
#* regular_prompt: This defines the string used to denote the R prompt.
#
#* continue_prompt: This is the string used to denote R's prompt for an incomplete statement (such as a multiple for loop).

  def prompt(regular_prompt="> ", continue_prompt="+ ")
    warn "'interactive' mode is off in this session " unless @interactive
    
    @readline ||= begin # initialize @readline at the first invocation
      require 'readline'
      proc{|prompt| Readline.readline(prompt, true)}
    rescue LoadError
      proc{|prompt|
        print prompt
        $stdout.flush
        gets.strip rescue nil
      }
    end
    
    cmds = []
    while true
      cmds << @readline.call(cmds.empty? ? regular_prompt : continue_prompt)
      if cmds[-1] then # the last "nil" input suspend current stack
        break if /^\s*exit\s*\(\s*\)\s*$/ =~ cmds[0]
        begin
          completed, eval_res = if_complete(cmds){|fun|
            [true, eval_engine("#{fun}()")]
          }
          next unless completed
          break unless eval_res
        rescue ParseError => e
          puts e.message
        end
      end
      cmds = []
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
#When assigning an array containing differing types of variables, RinRuby will follow R's conversion conventions. An array that contains any Strings will result in a character vector in R. If the array does not contain any Strings, but it does contain a Float or a large integer (in absolute value), then the result will be a numeric vector of Doubles in R. If there are only integers that are sufficiently small (in absolute value), then the result will be a numeric vector of integers in R.

  def assign(name, value)
    if_assignable(name){|fun|
      assign_engine(fun, value)
    }
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
    if_parseable(string){|fun|
      pull_engine("#{fun}()", singletons)
    }
  end

#The echo method controls whether the eval method displays output from R and, if echo is enabled, whether messages, warnings, and errors from stderr are also displayed.
#
#<b>Parameters that can be passed to the eval method</b>
#
#* enable: Setting enable to false will turn all output off until the echo command is used again with enable equal to true. The default is nil, which will return the current setting.
#
#* stderr: Setting stderr to true will force messages, warnings, and errors from R to be routed through stdout. Using stderr redirection is typically not needed, and is thus disabled by default. Echoing must be enabled when using stderr redirection.

  def echo(enable=nil, stderr=nil)
    next_enabled = (enable == nil) ? @echo_enabled : (enable ? true : false)
    next_stderr = case stderr
    when nil
      (next_enabled ? @echo_stderr : false) 
    else
      (stderr ? true : false)
    end
    
    if (next_enabled == false) && (next_stderr == true) then # prohibited combination
      raise "You can only redirect stderr if you are echoing is enabled."
    end
    
    if @echo_stderr != next_stderr then
      @writer.print(<<-__TEXT__)
        sink(#{'stdout(),' if next_stderr}type='message')
      __TEXT__
      @writer.flush
    end
    [@echo_enabled = next_enabled, @echo_stderr = next_stderr]
  end
  
  def echo_enabled=(enable)
    echo(enable).first
  end

  private

  #:stopdoc:
  RinRuby_Type_NotFound = -2
  RinRuby_Type_Unknown = -1
  [
    :Logical,
    :Integer,
    :Double,
    :Character,
    :Matrix,
  ].each_with_index{|type, i|
    Kernel.eval("RinRuby_Type_#{type} = i", binding)
  }

  RinRuby_Socket = "#{RinRuby_Env}$socket"
  RinRuby_Test_String = "#{RinRuby_Env}$test.string"
  RinRuby_Test_Result = "#{RinRuby_Env}$test.result"
  
  RinRuby_Eval_Flag = "RINRUBY.EVAL.FLAG"
  
  RinRuby_NA_R_Integer  = -(1 << 31)
  RinRuby_Max_R_Integer =  (1 << 31) - 1
  RinRuby_Min_R_Integer = -(1 << 31) + 1
  #:startdoc:

  def r_rinruby_socket_io
    @writer.print <<-EOF
      #{RinRuby_Socket} <- NULL
      #{RinRuby_Env}$session <- function(f){
        invisible(f(#{RinRuby_Socket}))
      }
      #{RinRuby_Env}$session.write <- function(writer){
        #{RinRuby_Env}$session(function(con){
          writer(function(v, ...){
            invisible(lapply(list(v, ...), function(v2){
                writeBin(v2, con, endian="#{RinRuby_Endian}")}))
          })
        })
      }
      #{RinRuby_Env}$session.read <- function(reader){
        #{RinRuby_Env}$session(function(con){
          reader(function(vtype, len){
            invisible(readBin(con, vtype(), len, endian="#{RinRuby_Endian}"))
          }, function(bytes){
            invisible(readChar(con, bytes, useBytes = T))
          })
        })
      }
    EOF
  end
  
  def r_rinruby_check
    @writer.print <<-EOF
    #{RinRuby_Env}$parseable <- function(var) {
      src <- srcfilecopy("<text>", lines=var, isFile=F)
      parsed <- try(parse(text=var, srcfile=src, keep.source=T), silent=TRUE)
      res <- function(){eval(parsed, env=globalenv())} # return evaluating function
      notification <- if(inherits(parsed, "try-error")){
        attributes(res)$parse.data <- getParseData(src)
        0L
      }else{
        1L
      }
      #{RinRuby_Env}$session.write(function(write){
        write(notification)
      })
      invisible(res)
    }
    #{RinRuby_Env}$last.parse.data <- function(data) {
      if(nrow(data) == 0L){
        c(0L, 0L, 0L)
      }else{
        endline <- data[max(data$line2) == data$line2, ]
        last.item <- endline[max(endline$col2) == endline$col2, ]
        eval(substitute(c(line2, col2, token == "';'"), last.item)) 
      }
    }
    #{RinRuby_Env}$assignable <- function(var) {
      parsed <- try(parse(text=paste0(var, ' <- .value')), silent=TRUE)
      is_invalid <- inherits(parsed, "try-error") || (length(parsed) != 1L)
      #{RinRuby_Env}$session.write(function(write){
        write(ifelse(is_invalid, 0L, 1L))
      })
      invisible(#{RinRuby_Env}$assign(var)) # return assigning function
    }
    EOF
  end
  # Create function on ruby to get values
  def r_rinruby_assign
    @writer.print <<-EOF
    #{RinRuby_Env}$assign <- function(var) {
      expr <- parse(text=paste0(var, " <- #{RinRuby_Env}$.value"))
      invisible(function(.value){
        #{RinRuby_Env}$.value <- .value
        eval(expr, envir=globalenv())
      })
    }
    #{RinRuby_Env}$assign.test.string <-
        #{RinRuby_Env}$assign("#{RinRuby_Test_String}")
    #{RinRuby_Env}$get_value <- function() {
      #{RinRuby_Env}$session.read(function(read, readchar){
        value <- NULL
        type <- read(integer, 1)
        length <- read(integer, 1)
        na.indices <- function(){
          read(integer, read(integer, 1)) + 1L
        }
        if ( type == #{RinRuby_Type_Logical} ) {
          value <- read(logical, length)
        } else if ( type == #{RinRuby_Type_Integer} ) {
          value <- read(integer, length)
        } else if ( type == #{RinRuby_Type_Double} ) {
          value <- read(double, length)
          value[na.indices()] <- NA
        } else if ( type == #{RinRuby_Type_Character} ) {
          value <- character(length)
          for(i in seq_len(length)){
            nbytes <- read(integer, 1)
            value[[i]] <- ifelse(nbytes >= 0, readchar(nbytes), NA)
          }
        }
        value
      })
    }
    EOF
  end

  def r_rinruby_pull
    @writer.print <<-EOF
#{RinRuby_Env}$pull <- function(var){
  #{RinRuby_Env}$session.write(function(write){
    if ( inherits(var ,"try-error") ) {
      write(#{RinRuby_Type_NotFound}L)
    } else {
      na.indices <- function(){
        indices <- which(is.na(var) & (!is.nan(var))) - 1L
        write(length(indices), indices)
      }
      if (is.matrix(var)) {
        write(#{RinRuby_Type_Matrix}L, nrow(var), ncol(var))
      } else if ( is.logical(var) ) {
        write(#{RinRuby_Type_Logical}L, length(var), as.integer(var))
      } else if ( is.integer(var) ) {
        write(#{RinRuby_Type_Integer}L, length(var), var)
      } else if ( is.double(var) ) {
        write(#{RinRuby_Type_Double}L, length(var), var)
        na.indices()
      } else if ( is.character(var) ) {
        write(#{RinRuby_Type_Character}L, length(var))
        for(i in var){
          if( is.na(i) ){
            write(as.integer(NA))
          }else{
            write(nchar(i, type="bytes"), i)
          }
        }
      } else {
        write(#{RinRuby_Type_Unknown}L)
      }
    }
  })
}
    EOF
  end
  
  def socket_session(&b)
    socket = @socket
    # TODO check still available connection?
    unless socket then
      t = Thread::new{socket = @server_socket.accept}
      @writer.print <<-EOF
        #{RinRuby_Socket} <- socketConnection( \
            "#{@hostname}", #{@port_number}, blocking=TRUE, open="rb")
      EOF
      @writer.puts(
          "on.exit(close(#{RinRuby_Socket}, add = T))") if @opts[:persistent]
      @writer.flush
      t.join
    end
    keep_socket = @opts[:persistent]
    res = nil
    begin
      res = b.call(socket)
    rescue
      keep_socket = false
      raise $!
    ensure
      if keep_socket
        @socket = socket
      else
        @socket = nil
        @writer.print <<-EOF
          close(#{RinRuby_Socket}); \
          #{RinRuby_Socket} <- NULL
        EOF
        @writer.flush
        socket.close
      end
    end
    res
  end
  
  class R_DataType
    ID = RinRuby_Type_Unknown
    class <<self
      def convertable?(value)
        false
      end
      def ===(value)
        convertable?(value)
      end
      def send(value, io)
        nil
      end
      def receive(io)
        nil
      end
    end
  end
  
  class R_Logical < R_DataType
    ID = RinRuby_Type_Logical
    CONVERT_TABLE = Hash[*({
          true => 1,
          false => 0, 
          nil => RinRuby_NA_R_Integer,
        }.collect{|k, v|
          [k, [v].pack('l')]
        }.flatten)]
    class <<self
      def convertable?(value)
        value.all?{|x| [true, false, nil].include?(x)}
      end
      def send(value, io)
        # Logical format: size, data, ...
        io.write([value.size].pack('l'))
        value.each{|x|
          io.write(CONVERT_TABLE[x])
        }
      end
      def receive(io)
        length = io.read(4).unpack('l').first
        io.read(4 * length).unpack("l*").collect{|v|
          (v == RinRuby_NA_R_Integer) ? nil : (v > 0)
        }
      end
    end
  end
  
  class R_Integer < R_DataType
    ID = RinRuby_Type_Integer
    class <<self
      def convertable?(value)
        value.all?{|x|
          (x == nil) ||
              (x.kind_of?(Integer) && (x >= RinRuby_Min_R_Integer) && (x <= RinRuby_Max_R_Integer))
        }
      end
      def send(value, io)
        # Integer format: size, data, ...
        io.write([value.size].pack('l'))
        value.each{|x|
          io.write([(x == nil) ? RinRuby_NA_R_Integer : x].pack('l'))
        }
      end
      def receive(io)
        length = io.read(4).unpack('l').first
        io.read(4 * length).unpack("l*").collect{|v|
          (v == RinRuby_NA_R_Integer) ? nil : v
        }
      end
    end
  end
  
  class R_Double < R_DataType
    ID = RinRuby_Type_Double
    class <<self
      def convertable?(value)
        value.all?{|x|
          (x == nil) || x.kind_of?(Numeric)
        }
      end
      def send(value, io)
        # Double format: data_size, data, ..., na_index_size, na_index, ...
        io.write([value.size].pack('l'))
        nils = []
        value.each.with_index{|x, i|
          if x == nil then
            nils << i
            io.write([Float::NAN].pack('D'))
          else
            io.write([x.to_f].pack('D'))
          end
        }
        io.write(([nils.size] + nils).pack('l*'))
        value
      end
      def receive(io)
        length = io.read(4).unpack('l').first
        res = io.read(8 * length).unpack("D*")
        na_indices = io.read(4).unpack('l').first
        io.read(4 * na_indices).unpack("l*").each{|i| res[i] = nil}
        res
      end
    end
  end
  
  class R_Character < R_DataType
    ID = RinRuby_Type_Character
    class <<self
      def convertable?(value)
        value.all?{|x|
          (x == nil) || x.kind_of?(String)
        }
      end
      def send(value, io)
        # Character format: data_size, data1_bytes, data1, data2_bytes, data2, ...
        io.write([value.size].pack('l'))
        value.each{|x|
          if x then
            bytes = x.to_s.bytes # TODO: taking care of encoding difference
            io.write(([bytes.size] + bytes).pack('lC*')) # .bytes.pack("C*").encoding equals to "ASCII-8BIT"
          else
            io.write([RinRuby_NA_R_Integer].pack('l'))
          end
        }
        value
      end
      def receive(io)
        length = io.read(4).unpack('l').first
        Array.new(length){|i|
          nchar = io.read(4).unpack('l')[0]
          # negative nchar means NA, and "+ 1" for zero-terminated string
          (nchar >= 0) ? io.read(nchar + 1)[0..-2] : nil
        }
      end
    end
  end
  
  def assign_engine(fun, value, r_type = nil)
    raise EngineClosed if @writer.closed?
    
    original_value = value
    
    r_exp = "#{fun}(#{RinRuby_Env}$get_value())"
    
    if value.kind_of?(::Matrix) # assignment for matrices
      r_exp = "#{fun}(matrix(#{RinRuby_Env}$get_value(), " \
          "nrow=#{value.row_size}, ncol=#{value.column_size}, byrow=T))"
      value = value.row_vectors.collect{|row| row.to_a}.flatten
    elsif !value.kind_of?(Enumerable) then # check each
      value = [value]
    end
    
    r_type ||= [
      R_Logical,
      R_Integer,
      R_Double,
      R_Character,
    ].find{|k|
      k === value
    }
    raise "Unsupported data type on Ruby's end" unless r_type
    
    socket_session{|socket|
      @writer.puts(r_exp)
      @writer.flush
      socket.write([r_type::ID].pack('l'))
      r_type.send(value, socket)
    }
    
    original_value
  end

  def pull_engine(string, singletons = true)
    raise EngineClosed if @writer.closed?
    
    pull_proc = proc{|var, socket|
      @writer.puts "#{RinRuby_Env}$pull(try(#{var}))"
      @writer.flush
      type = socket.read(4).unpack('l').first
      case type
      when RinRuby_Type_Unknown
        raise "Unsupported data type on R's end"
      when RinRuby_Type_NotFound
        next nil
      when RinRuby_Type_Matrix
        rows, cols = socket.read(8).unpack('l*')
        next Matrix.rows( # get rowwise flatten vector
            [pull_proc.call("as.vector(t(#{var}))", socket)].flatten.each_slice(cols).to_a,
            false)
      end
      
      r_type = [
        R_Logical,
        R_Integer,
        R_Double,
        R_Character,
      ].find{|k|
        k::ID == type
      }
      
      raise "Unsupported data type on Ruby's end" unless r_type
      
      res = r_type.receive(socket)
      (!singletons) && (res.size == 1) ? res[0] : res
    }
    socket_session{|socket|
      pull_proc.call(string, socket)
    }
  end

  def if_passed(string, r_func, opt = {}, &then_proc)
    assign_engine("#{RinRuby_Env}$assign.test.string", string, R_Character)
    res = socket_session{|socket|
      @writer.puts "#{RinRuby_Test_Result} <- #{r_func}(#{RinRuby_Test_String})"
      @writer.flush
      socket.read(4).unpack('l').first > 0
    }
    unless res then
      raise ParseError, "Parse error: #{string}" unless opt[:error_proc]
      opt[:error_proc].call(RinRuby_Test_Result)
      return false
    end
    then_proc ? then_proc.call(RinRuby_Test_Result) : true
  end
  def if_parseable(string, opt = {}, &then_proc)
    if_passed(string, "#{RinRuby_Env}$parseable", opt, &then_proc)
  end
  def if_assignable(name, opt = {}, &then_proc)
    if_passed(name, "#{RinRuby_Env}$assignable", opt, &then_proc)
  end
  
  def if_complete(lines, &then_proc)
    if_parseable(lines, {
      :error_proc => proc{|var|
        # extract last parsed position
        l2, c2, is_separator = pull_engine(
            "#{RinRuby_Env}$last.parse.data(attr(#{var}, 'parse.data'))")
        
        # detect unrecoverable error
        l2_max = lines.size + is_separator
        while (l2 > 0) and (l2 <= l2_max) # parse completion is before or on the last line
          end_line = lines[l2 - 1]
          break if (l2 == l2_max) and (end_line[c2..-1] =~ /^\s*$/)
          raise ParseError, <<-__TEXT__
Unrecoverable parse error: #{end_line}
                           #{' ' * (c2 - 1)}^...
          __TEXT__
        end
      }
    }, &then_proc)
  end
  
  def complete?(string)
    if_complete(string.lines)
  end
  public :complete?
  
  def eval_engine(r_expr, &echo_proc)
    raise EngineClosed if (@writer.closed? || @reader.closed?)
    
    run_num = (@eval_count += 1)
    @writer.print(<<-__TEXT__)
{#{r_expr}}
print('#{RinRuby_Eval_Flag}.#{run_num}')
    __TEXT__
    @writer.flush
    
    echo_proc ||= proc{|raw, stripped|
      puts stripped.chomp("")
      $stdout.flush
    }
    
    res = false
    t = Thread::new{
      while (line = @reader.gets)
        # TODO I18N; force_encoding('origin').encode('UTF-8')
        case (stripped = line.gsub(/\x1B\[[0-?]*[ -\/]*[@-~]/, '')) # drop escape sequence
        when /\"#{RinRuby_Eval_Flag}\.(\d+)\"/
          next if $1.to_i != run_num
          res = true 
          break
        end
        echo_proc.call(line, stripped)
      end
    }
    
    int_received = false
    int_handler_orig = Signal.trap(:INT){
      Signal.trap(:INT){} # ignore multiple reception 
      int_received = true
      if @executable =~ /Rterm\.exe["']?$/
        @writer.print [0x1B].pack('C') # simulate ESC key
        @writer.flush
      else
        Process.kill(:INT, @r_pid)
      end
      t.kill
    }
    
    begin
      t.join
    ensure
      Signal.trap(:INT, int_handler_orig)
      Process.kill(:INT, $$) if int_received
    end
    res
  end
  
  class << self
    # Remove invalid byte sequence
    if RUBY_VERSION >= "2.1.0" then
      define_method(:scrub){|str| str.scrub}
    elsif RUBY_VERSION >= "1.9.0" then
      define_method(:scrub){|str| str.chars.collect{|c| (c.valid_encoding?) ? c : '*'}.join}
    else
      define_method(:scrub){|str| str}
    end
  
    def find_R_dir_on_windows(cygwin = false, &b)
      res = []
      b ||= proc{}
      
      # Firstly, check registry
      ['HKEY_LOCAL_MACHINE', 'HKEY_CURRENT_USER'].each{|root|
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
            v = `cygpath '#{`regtool get #{args.join(' ')}`.strip}'`.strip
            b.call((res << v)[-1]) unless (v.empty? || res.include?(v))
          }
        else
          scrub(`reg query "#{root}\\Software\\R-core" /v "InstallPath" /s 2>nul`).each_line{|line|
            next unless line.strip =~ /^\s*InstallPath\s+REG_SZ\s+(.+)/
            b.call((res << $1)[-1]) unless res.include?($1)
          }
        end
      }
      
      # Secondly, check default install path
      ["Program Files", "Program Files (x86)"].each{|prog_dir|
        Dir::glob(File::join(cygwin ? "/cygdrive/c" : "C:", prog_dir, "R", "*")).each{|path|
          b.call((res << path)[-1]) unless res.include?(path)
        }
      }
      
      res
    end
  
    def find_R_on_windows(cygwin = false)
      return 'R' if cygwin && system('which R > /dev/nul 2>&1')
      
      find_R_dir_on_windows(cygwin){|path|
        ['bin', 'bin/x64', 'bin/i386'].product(
            cygwin ? [path.gsub(' ','\ '), path] : [path.gsub('\\','/')]).each{|bin_dir, base_dir| 
          r_exe = File::join(base_dir, bin_dir, "Rterm.exe")
          return %Q<"#{r_exe}"> if File.exists?(r_exe)
        }
      }
      raise "Cannot locate R executable"
    end
  end

end

if ! defined?(R)
  #R is an instance of RinRuby.  If for some reason the user does not want R to be initialized (to save system resources), then create a default value for R (e.g., <b>R=2</b> ) in which case RinRuby will not overwrite the value of R.

  R = RinRuby.new
end

