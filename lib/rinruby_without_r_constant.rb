#=RinRuby: Accessing the R[http://www.r-project.org] interpreter from pure Ruby
#
#RinRuby is a Ruby library that integrates the R interpreter in Ruby, making R's statistical routines and graphics available within Ruby.  The library consists of a single Ruby script that is simple to install and does not require any special compilation or installation of R.  Since the library is 100% pure Ruby, it works on a variety of operating systems, Ruby implementations, and versions of R.  RinRuby's methods are simple, making for readable code.  The {website [rinruby.ddahl.org]}[http://rinruby.ddahl.org] describes RinRuby usage, provides comprehensive documentation, gives several examples, and discusses RinRuby's implementation.
#
require 'matrix'

class RinRubyWithoutRConstant

  require 'socket'

  attr_reader :interactive
  attr_reader :readline
  # Exception for closed engine
  EngineClosed=Class.new(Exception)
  # Parse error
  ParseError=Class.new(Exception)

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
    default_opts= {:echo=>true, :interactive=>true, :executable=>nil, :port_number=>38542, :port_width=>1000, :hostname=>'127.0.0.1'}

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
    echo(nil,true) if @platform =~ /.*-java/      # Redirect error messages on the Java platform
  end

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

  def assign(name, value)
     raise EngineClosed if @engine.closed?
    if assignable?(name)
      assign_engine(name,value)
    else
      raise ParseError, "Parse error"
    end
  end

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
      `reg query "#{root}\\Software\\R-core\\R" /v "InstallPath"`.split("\n").each do |line|
        next if line !~ /^\s+InstallPath\s+REG_SZ\s+(.*)/
        path = $1
        while path.chomp!
        end
        break
      end
      break if path != '?'
    end
    raise "Cannot locate R executable" if path == '?'
    if cygwin
      path = `cygpath '#{path}'`
      while path.chomp!
      end
      path.gsub!(' ','\ ')
    else
      path.gsub!('\\','/')
    end
    for hierarchy in [ 'bin', 'bin/i386', 'bin/x64' ]
      target = "#{path}/#{hierarchy}/Rterm.exe"
      if File.exists? target
        return %Q<"#{target}">
      end
    end
    raise "Cannot locate R executable"
  end
end
