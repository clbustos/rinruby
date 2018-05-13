require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require 'rinruby_without_r_constant'

describe RinRubyWithoutRConstant do
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
        skip("Difficult to test without specific location of R executable on Windows")
      else      
      R.quit
      r=RinRubyWithoutRConstant.new(false, false, "R", 38525, 1)

      expect(r.echo_enabled).to be false
      r.interactive.should be false
      r.executable.should=="R"
      r.port_number.should==38525
      r.port_width.should==1
      end
    end
    it "should accept :echo and :interactive parameters" do
      r=RinRubyWithoutRConstant.new(:echo=>false, :interactive=>false)
      r.echo_enabled.should be false
      r.interactive.should be false
      
    end
    it "should accept :port_number" do
      port=38542+rand(3)
      r=RinRubyWithoutRConstant.new(:port_number=>port,:port_width=>1)
      r.port_number.should==port
      r.quit
    end
    it "should accept :port_width" do
      port=38542
      port_width=rand(10)+1
      r=RinRubyWithoutRConstant.new(:port=>port, :port_width=>port_width)
      expect(r.port_width).to be == port_width
      r.port_number.should satisfy {|v| v>=port and v < port+port_width}
    end
  end
  before do
    @rr = RinRubyWithoutRConstant.new
    @rr.echo(false)
  end
  subject {@rr}
  context "basic methods" do 
    it {should respond_to :eval}
    it {should respond_to :quit}
    it {should respond_to :assign}
    it {should respond_to :pull}
    it {should respond_to :quit}
    it {should respond_to :echo}
    it "return correct values for complete?" do
      @rr.eval("x<-1").should be true
    end
    it "return false for complete? for incorrect expressions" do
      @rr.complete?("x<-").should be false
    end
    it "correct eval should return true" do 
      @rr.complete?("x<-1").should be true
    end
    it "incorrect eval should raise an ParseError" do
      lambda {@rr.eval("x<-")}.should raise_error(RinRubyWithoutRConstant::ParseError)
    end
  end
  context "on assing" do 
    it "should assign correctly" do
      x=rand
      @rr.assign("x",x)
      @rr.pull("x").should==x
    end
    it "should be the same using assign than R#= methods" do
      x=rand
      @rr.assign("x1",x)
      @rr.x2=x
      @rr.pull("x1").should==x
      @rr.pull("x2").should==x
    end
    it "should raise an ArgumentError error on setter with 0 parameters" do
      lambda {@rr.unknown_method=() }.should raise_error(ArgumentError)
    end
    
  end
  context "on pull" do
    it "should be the same using pull than R# methods" do
      x=rand
      @rr.x=x
      @rr.pull("x").should==x
      @rr.x.should==x
    end
    it "should raise an NoMethod error on getter with 1 or more parameters" do
      lambda {@rr.unknown_method(1) }.should raise_error(NoMethodError)
    end
    
    it "should pull a String" do
      @rr.eval("x<-'Value'")
      @rr.pull('x').should=='Value'
    end
    it "should pull an Integer" do
      @rr.eval("x<-1")
      @rr.pull('x').should==1
    end
    it "should pull a Float" do
      @rr.eval("x<-1.5")
      @rr.pull('x').should==1.5
    end
    it "should pull an Array of Numeric" do
      @rr.eval("x<-c(1,2.5,3)")
      @rr.pull('x').should==[1,2.5,3]
    end
    it "should pull an Array of strings" do
      @rr.eval("x<-c('a','b')")
      @rr.pull('x').should==['a','b']
    end

    it "should push a Matrix" do
      matrix=Matrix[[rand,rand,rand],[rand,rand,rand]]
      lambda {@rr.assign('x',matrix)}.should_not raise_error
      rx=@rr.x
      matrix.row_size.times {|i|
        matrix.column_size.times {|j|
          matrix[i,j].should be_within(1e-10).of(rx[i,j])
        }
      }
    end
    
  end

  context "on quit" do
    before(:each) do
      @r=RinRubyWithoutRConstant.new(:echo=>false)
    end
    it "return true" do
      @r.quit.should be true
    end
    it "returns an error if used again" do
      @r.quit
      lambda {@r.eval("x=1")}.should raise_error(RinRubyWithoutRConstant::EngineClosed)
    end
  end
  

end
