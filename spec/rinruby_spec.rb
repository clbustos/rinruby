require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require 'rinruby'
puts "RinRuby #{RinRuby::VERSION} specification"

describe RinRuby do
  describe "on init" do
    let(:params){
      {
        :echo_enabled => false, 
        :interactive => false, 
        :executable => nil, 
        :port_number => 38500, 
        :port_width => 1,
      }
    }
    let(:r){
      RinRuby.new(*([:echo_enabled, :interactive, :executable, :port_number, :port_width].collect{|k| params[k]}))
    }
    it "should accept parameters as specified on Dahl & Crawford(2009)" do
      expect(r.echo_enabled).to be_falsy
      expect(r.interactive).to be_falsy
      expect(r.port_number).to eq(params[:port_number])
      expect(r.port_width).to eq(params[:port_width])
      case r.instance_variable_get(:@platform)
      when /^windows/ then
        expect(r.executable).to match(/Rterm\.exe["']?$/)
      else
        expect(r.executable).to eq("R")
      end      
    end
    it "should accept custom :port_number" do
      params.merge!(:port_number => 38442+rand(3))
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
  before do
    R.echo(false)
  end
  subject {R}
  context "basic methods" do 
    it {is_expected.to respond_to(:eval)}
    it {is_expected.to respond_to(:quit)}
    it {is_expected.to respond_to(:assign)}
    it {is_expected.to respond_to(:pull)}
    it {is_expected.to respond_to(:quit)}
    it {is_expected.to respond_to(:echo)}
    it "return correct values for complete?" do
      expect(R.eval("x<-1")).to be_truthy
    end
    it "return false for complete? for incorrect expressions" do
      expect(R.complete?("x<-")).to be_falsy
    end
    it "correct eval should return true" do 
      expect(R.complete?("x<-1")).to be_truthy
    end
    it "incorrect eval should raise an ParseError" do
      expect{R.eval("x<-")}.to raise_error(RinRuby::ParseError)
    end
  end
  context "on assing" do
    let(:x){rand} 
    it "should assign correctly" do
      R.assign("x",x)
      expect(R.pull("x")).to eq(x)
    end
    it "should be the same using assign than R#= methods" do
      R.assign("x1",x)
      R.x2=x
      expect(R.pull("x1")).to eq(x)
      expect(R.pull("x2")).to eq(x)
    end
    it "should raise an ArgumentError error on setter with 0 parameters" do
      expect{R.unknown_method=() }.to raise_error(ArgumentError)
    end
  end
  context "on pull" do
    it "should be the same using pull than R# methods" do
      x=rand
      R.x=x
      expect(R.pull("x")).to eq(x)
      expect(R.x).to eq(x)
    end
    it "should raise an NoMethod error on getter with 1 or more parameters" do
      expect{R.unknown_method(1) }.to raise_error(NoMethodError)
    end
    
    it "should pull a String" do
      R.eval("x<-'Value'")
      expect(R.pull('x')).to eq('Value')
    end
    it "should pull an Integer" do
      R.eval("x<-1")
      expect(R.pull('x')).to eq(1)
    end
    it "should pull a Float" do
      R.eval("x<-1.5")
      expect(R.pull('x')).to eq(1.5)
    end
    it "should pull an Array of Numeric" do
      R.eval("x<-c(1,2.5,3)")
      expect(R.pull('x')).to eq([1,2.5,3])
    end
    it "should pull an Array of strings" do
      R.eval("x<-c('a','b')")
      expect(R.pull('x')).to eq(['a','b'])
    end

    it "should push a Matrix" do
      matrix=Matrix::build(100, 200){|i, j| rand} # 100 x 200 matrix
      expect{R.assign('x',matrix)}.not_to raise_error
      rx=R.x
      matrix.row_size.times {|i|
        matrix.column_size.times {|j|
          expect(matrix[i,j]).to be_within(1e-10).of(rx[i,j])
        }
      }
    end
    
  end

  context "on quit" do
    let(:r){RinRuby.new(:echo=>false)}
    it "return true" do
      expect(r.quit).to be_truthy
    end
    it "returns an error if used again" do
      r.quit
      expect{r.eval("x=1")}.to raise_error(RinRuby::EngineClosed)
    end
  end
end
