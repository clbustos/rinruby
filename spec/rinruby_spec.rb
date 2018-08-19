require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require 'rinruby'
puts "RinRuby #{RinRuby::VERSION} specification"

shared_examples 'RinRubyCore' do
  let(:params){
    {
      :echo_enabled => false, 
      :interactive => false, 
      :executable => nil, 
      :port_number => 38500,
      :port_width => 1000,
    }
  }
  describe "on init" do
    after{(r.quit rescue nil) if defined?(r)}
    it "should accept parameters as specified on Dahl & Crawford(2009)" do
      expect(r.echo_enabled).to be_falsy
      expect(r.interactive).to be_falsy
      case r.instance_variable_get(:@platform)
      when /^windows/ then
        expect(r.executable).to match(/Rterm\.exe["']?$/)
      else
        expect(r.executable).to eq("R")
      end      
    end
    it "should accept :echo and :interactive parameters" do
      params.merge!(:echo_enabled => true, :interactive => true)
      expect(r.echo_enabled).to be_truthy
      expect(r.interactive).to be_truthy
    end
    it "should accept custom :port_number" do
      params.merge!(:port_number => 38442+rand(3), :port_width => 1)
      expect(r.port_number).to eq(params[:port_number])
    end
    it "should accept custom :port_width" do
      params.merge!(:port_number => 38442, :port_width => rand(10)+1)
      expect(r.port_width).to eq(params[:port_width])
      expect(r.port_number).to satisfy {|v| 
        ((params[:port_number])...(params[:port_number] + params[:port_width])).include?(v)
      }
    end
  end
  
  describe "R interface" do
    # In before(:each) or let(including subject) blocks, Assignment to instance variable 
    # having a same name defined in before(:all) will not work intentionally, 
    # because a new instance variable will be created for the following examples.
    # For workaround, two-step indirect assignment to a hash created in before(:all) is applied. 
    before(:all){@cached_env = {:r => nil}} # make placeholder
    subject{@cached_env[:r] ||= r}
    after(:all){@cached_env[:r].quit rescue nil}
    describe "basic methods" do 
      it {is_expected.to respond_to(:eval)}
      it {is_expected.to respond_to(:assign)}
      it {is_expected.to respond_to(:pull)}
      it {is_expected.to respond_to(:quit)}
      it {is_expected.to respond_to(:echo)}
      it "return correct values for complete?" do
        expect(subject.eval("x<-1")).to be_truthy
      end
      it "return false for complete? for incorrect expressions" do
        expect(subject.complete?("x<-")).to be_falsy
      end
      it "correct eval should return true" do 
        expect(subject.complete?("x<-1")).to be_truthy
      end
      it "incorrect eval should raise an ParseError" do
        expect{subject.eval("x<-")}.to raise_error(RinRuby::ParseError)
      end
    end
    
    context "on pull" do
      it "should pull a String" do
        subject.eval("x<-'Value'")
        expect(subject.pull('x')).to eql('Value')
      end
      it "should pull an Integer" do
        [0x12345678, -0x12345678].each{|v| # for check endian, and range
          subject.eval("x<-#{v}L")
          expect(subject.pull('x')).to eql(v)
        }
      end
      it "should pull a Float" do
        [1.5, 1.0].each{|v|
          subject.eval("x<-#{v}e0")
          expect(subject.pull('x')).to eql(v)
        }
        [1 << 32, -(1 << 32)].each{|v| # big integer will be treated as float
          subject.eval("x<-#{v}")
          expect(subject.pull('x')).to eql(v.to_f)
        }
      end
      it "should pull a Logical" do
        {:T => true, :F => false}.each{|k, v|
          subject.eval("x<-#{k}")
          expect(subject.pull('x')).to eql(v)
        }
      end
      it "should pull an Array of String" do
        subject.eval("x<-c('a','b')")
        expect(subject.pull('x')).to eql(['a','b'])
      end
      it "should pull an Array of Integer" do
        subject.eval("x<-c(1L,2L,-5L,-3L)")
        expect(subject.pull('x')).to eql([1,2,-5,-3])
      end
      it "should pull an Array of Float" do
        subject.eval("x<-c(1.1,2.2,5,3)")
        expect(subject.pull('x')).to eql([1.1,2.2,5.0,3.0])
        subject.eval("x<-c(1L,2L,5L,3.0)") # numeric vector 
        expect(subject.pull('x')).to eql([1.0,2.0,5.0,3.0])
      end
      it "should pull an Array of Logical" do
        subject.eval("x<-c(T, F)")
        expect(subject.pull('x')).to eql([true, false])
      end

      it "should pull a Matrix" do
        [
          proc{ # integer matrix
            v = rand(100000000) # get 8 digits
            [v, "#{v}L"]
          },
          proc{ # float matrix
            v = rand(100000000) # get 8 digits
            [Float("0.#{v}"), "0.#{v}"]
          },
        ].each{|gen_proc|
          nrow, ncol = [10, 10] # 10 x 10 small matrix
          subject.eval("x<-matrix(nrow=#{nrow}, ncol=#{ncol})")
          rx = Matrix[*((1..nrow).collect{|i|
            (1..ncol).collect{|j|
              v_rb, v_R = gen_proc.call
              subject.eval("x[#{i},#{j}]<-#{v_R}")
              v_rb
            }
          })]
          expect(subject.pull('x')).to eql(rx)
        }
      end
      
      it "should be the same using pull than R# methods" do
        subject.eval("x <- #{rand(100000000)}")
        expect(subject.pull("x")).to eql(subject.x)
      end
      it "should raise an NoMethod error on getter with 1 or more parameters" do
        expect{subject.unknown_method(1)}.to raise_error(NoMethodError)
      end
    end
    
    context "on assign (PREREQUISITE: all pull tests are passed)" do
      it "should assign a String" do
        x = 'Value'
        subject.assign("x", x)
        expect(subject.pull('x')).to eql(x)
      end
      it "should assign an Integer" do
        [0x12345678, -0x12345678].each{|x|
          subject.assign("x", x)
          expect(subject.pull('x')).to eql(x)
        }
      end
      it "should assign a Float" do
        [rand, 1 << 32, -(1 << 32)].each{|x|
          subject.assign("x", x)
          expect(subject.pull('x')).to eql(x.to_f)
        }
      end
      it "should assign a Logical" do
        [true, false].each{|x|
          subject.assign("x", x)
          expect(subject.pull('x')).to eql(x)
        }
      end
      it "should assign an Array of String" do
        x = ['a', 'b']
        subject.assign("x", x)
        expect(subject.pull('x')).to eql(x)
      end
      it "should assign an Array of Integer" do
        x = [1, 2, -5, -3]
        subject.assign("x", x)
        expect(subject.pull('x')).to eql(x)
      end
      it "should assign an Array of Float" do
        subject.assign("x", [1.1, 2.2, 5, 3])
        expect(subject.pull('x')).to eql([1.1,2.2,5.0,3.0])
      end
      it "should assign an Array of Logical" do
        x = [true, false]
        subject.assign("x", x)
        expect(subject.pull('x')).to eql(x)
      end

      it "should assign a Matrix" do
        [
          proc{rand(100000000)}, # integer matrix
          proc{rand}, # float matrix
        ].each{|gen_proc|
          x = Matrix::build(100, 200){|i, j| gen_proc.call} # 100 x 200 matrix
          subject.assign("x", x)
          expect(subject.pull('x')).to eql(x)
        }
      end
      
      it "should be the same using assign than R#= methods" do
        x = rand(100000000)
        subject.assign("x1", x)
        subject.x2 = x
        expect(subject.pull("x1")).to eql(subject.pull("x2"))
      end
      it "should raise an ArgumentError error on setter with 0 parameters" do
        expect{subject.unknown_method=() }.to raise_error(ArgumentError)
      end
    end 
  end
  
  context "on quit" do
    it "return true" do
      expect(r.quit).to be_truthy
    end
    it "returns an error if used again" do
      r.quit
      expect{r.eval("x=1")}.to raise_error(RinRuby::EngineClosed)
    end
  end
end

describe RinRuby do
  let(:r){
    RinRuby.new(*([:echo_enabled, :interactive, :executable, :port_number, :port_width].collect{|k| params[k]}))
  }
  include_examples 'RinRubyCore'
end