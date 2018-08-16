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
    context "on assign" do
      let(:x){rand} 
      it "should assign correctly" do
        subject.assign("x",x)
        expect(subject.pull("x")).to eq(x)
      end
      it "should be the same using assign than R#= methods" do
        subject.assign("x1",x)
        subject.x2=x
        expect(subject.pull("x1")).to eq(x)
        expect(subject.pull("x2")).to eq(x)
      end
      it "should raise an ArgumentError error on setter with 0 parameters" do
        expect{subject.unknown_method=() }.to raise_error(ArgumentError)
      end
    end
    context "on pull" do
      it "should be the same using pull than R# methods" do
        x=rand
        subject.x=x
        expect(subject.pull("x")).to eq(x)
        expect(subject.x).to eq(x)
      end
      it "should raise an NoMethod error on getter with 1 or more parameters" do
        expect{subject.unknown_method(1) }.to raise_error(NoMethodError)
      end

      it "should pull a String" do
        subject.eval("x<-'Value'")
        expect(subject.pull('x')).to eq('Value')
      end
      it "should pull an Integer" do
        subject.eval("x<-1")
        expect(subject.pull('x')).to eq(1)
      end
      it "should pull a Float" do
        subject.eval("x<-1.5")
        expect(subject.pull('x')).to eq(1.5)
      end
      it "should pull an Array of Numeric" do
        subject.eval("x<-c(1,2.5,3)")
        expect(subject.pull('x')).to eq([1,2.5,3])
      end
      it "should pull an Array of strings" do
        subject.eval("x<-c('a','b')")
        expect(subject.pull('x')).to eq(['a','b'])
      end

      it "should push a Matrix" do
        matrix=Matrix::build(100, 200){|i, j| rand} # 100 x 200 matrix
        expect{subject.assign('x',matrix)}.not_to raise_error
        rx=subject.x
        matrix.row_size.times {|i|
          matrix.column_size.times {|j|
            expect(matrix[i,j]).to be_within(1e-10).of(rx[i,j])
          }
        }
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