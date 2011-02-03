require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
puts "RinRuby #{RinRuby::VERSION} specification"

describe RinRuby do
  describe "on init" do
    it "should accept parameters as specified on Dahl & Crawford(2009)" do
      
      platform = case RUBY_PLATFORM
      when /mswin/ then 'windows'
      when /mingw/ then 'windows'
      when /bccwin/ then 'windows'
      else 
        "other"
      end
      if platform=='windows'
        pending("Difficult to test without specific location of R executable on Windows")
      else      
      
      r=RinRuby.new(false, false, "R", 38500, 1)
      r.echo_enabled.should_not be_true
      r.interactive.should_not be_true
      r.executable.should=="R"
      r.port_number.should==38500
      r.port_width.should==1      
      end
    end
    it "should accept :echo and :interactive parameters" do
      r=RinRuby.new(:echo=>false, :interactive=>false)
      r.echo_enabled.should_not be_true
      r.interactive.should_not be_true
      
    end
    it "should accept :port_number" do
      port=38442+rand(3)
      r=RinRuby.new(:port_number=>port,:port_width=>1)
      r.port_number.should==port
      r.quit
    end
    it "should accept :port_width" do
      port=38442
      port_width=rand(10)
      r=RinRuby.new(:port=>port, :port_width=>port_width)
      r.port_width.should==port_width
      r.port_number.should satisfy {|v| v>=port and v < port+port_width}
    end
  end
  before do
    R.echo(false)
  end
  subject {R}
  context "basic methods" do 
    it {should respond_to :eval}
    it {should respond_to :quit}
    it {should respond_to :assign}
    it {should respond_to :pull}
    it {should respond_to :quit}
    it {should respond_to :echo}
    it "return correct values for complete?" do
      R.eval("x<-1").should be_true
    end
    it "return false for complete? for incorrect expressions" do
      R.complete?("x<-").should be_false
    end
    it "correct eval should return true" do 
      R.complete?("x<-1").should be_true
    end
    it "incorrect eval should raise an ParseError" do
      lambda {R.eval("x<-")}.should raise_error(RinRuby::ParseError)
    end
  end
  context "on assing" do 
    it "should assign correctly" do
      x=rand
      R.assign("x",x)
      R.pull("x").should==x
    end
    it "should be the same using assign than R#= methods" do
      x=rand
      R.assign("x1",x)
      R.x2=x
      R.pull("x1").should==x
      R.pull("x2").should==x
    end
    it "should raise an ArgumentError error on setter with 0 parameters" do
      lambda {R.unknown_method=() }.should raise_error(ArgumentError)
    end
    
  end
  context "on pull" do
    it "should be the same using pull than R# methods" do
      x=rand
      R.x=x
      R.pull("x").should==x
      R.x.should==x
    end
    it "should raise an NoMethod error on getter with 1 or more parameters" do
      lambda {R.unknown_method(1) }.should raise_error(NoMethodError)
    end
    
    it "should pull a String" do
      R.eval("x<-'Value'")
      R.pull('x').should=='Value'
    end
    it "should pull an Integer" do
      R.eval("x<-1")
      R.pull('x').should==1
    end
    it "should pull a Float" do
      R.eval("x<-1.5")
      R.pull('x').should==1.5
    end
    it "should pull an Array of Numeric" do
      R.eval("x<-c(1,2.5,3)")
      R.pull('x').should==[1,2.5,3]
    end
    it "should pull an Array of strings" do
      R.eval("x<-c('a','b')")
      R.pull('x').should==['a','b']
    end

    it "should push a Matrix" do
      matrix=Matrix[[rand,rand,rand],[rand,rand,rand]]
      lambda {R.assign('x',matrix)}.should_not raise_error
      rx=R.x
      matrix.row_size.times {|i|
        matrix.column_size.times {|j|
          matrix[i,j].should be_within(1e-10).of(rx[i,j])
        }
      }
    end
    
  end

  context "on quit" do
    before(:each) do
      @r=RinRuby.new(:echo=>false)
    end
    it "return true" do
      @r.quit.should be_true
    end
    it "returns an error if used again" do
      @r.quit
      lambda {@r.eval("x=1")}.should raise_error(RinRuby::EngineClosed)
    end
  end
  

end
