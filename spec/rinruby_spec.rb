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
      when /^windows-cygwin/ then
        expect(r.executable).to match(/(^R|Rterm\.exe["']?)$/)
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
      it {is_expected.to respond_to(:prompt)}
      it "return true for complete? for correct expressions" do
        ["", "x<-1", "x<-\n1", "'123\n456'", "1+\n2+\n3"].each{|str|
          expect(subject.complete?(str)).to be true
        }
      end
      it "return false for complete? for incorrect expressions" do
        ["x<-", "'123\n", "1+\n2+\n"].each{|str|
          expect(subject.complete?(str)).to be false
        }
      end
      it "raise error for complete? for unrecoverable expression" do
        [";", "x<-;"].each{|str|
          expect{subject.complete?(str)}.to raise_error(RinRuby::ParseError)
        }
      end
      it "correct eval should return true" do
        ["", "x<-1", "x<-\n1", "'123\n456'"].each{|str|
          expect(subject.eval(str)).to be_truthy
        }
      end
      it "incorrect eval should raise an ParseError" do
        [
          "x<-", "'123\n", # incomplete
          ";", "x<-;", # unrecoverable
        ].each{|str|
          expect{subject.eval(str)}.to raise_error(RinRuby::ParseError)
        }
      end
    end
    
    def gen_matrix_cmp_per_elm_proc(&cmp_proc)
      proc{|a, b|
        expect(a.row_size).to eql(b.row_size)
        expect(a.column_size).to eql(b.column_size)
        a.row_size.times{|i|
          a.column_size.times{|j|
            cmp_proc.call(a[i,j], b[i,j])
          }
        }
      }
    end
    
    context "on pull" do
      it "should pull a Character" do
        ['Value', ''].each{|v| # normal string and zero-length string
          subject.eval("x<-'#{v}'")
          expect(subject.pull('x')).to eql(v)
        }
        subject.eval("x<-as.character(NA)")
        expect(subject.pull('x')).to eql(nil)
      end
      it "should pull an Integer" do
        [0x12345678, -0x12345678].each{|v| # for check endian, and range
          subject.eval("x<-#{v}L")
          expect(subject.pull('x')).to eql(v)
        }
      end
      it "should pull a Double" do
        [1.5, 1.0].each{|v|
          subject.eval("x<-#{v}e0")
          expect(subject.pull('x')).to eql(v)
        }
        [1 << 32, -(1 << 32)].each{|v| # big integer will be treated as double
          subject.eval("x<-#{v}")
          expect(subject.pull('x')).to eql(v.to_f)
        }
        subject.eval("x<-NaN")
        expect(subject.pull('x').nan?).to be_truthy
        subject.eval("x<-as.numeric(NA)")
        expect(subject.pull('x')).to eql(nil)
      end
      it "should pull a Logical" do
        {:T => true, :F => false, :NA => nil}.each{|k, v|
          subject.eval("x<-#{k}")
          expect(subject.pull('x')).to eql(v)
        }
      end
      it "should pull an Array of Character" do
        {
          "c('a','b','',NA)" => ['a','b','',nil],
          "as.character(NULL)" => [],
        }.each{|k, v|
          subject.eval("x<-#{k}")
          expect(subject.pull('x')).to eql(v)
        }
      end
      it "should pull an Array of Integer" do
        {
          "c(1L,2L,-5L,-3L,NA)" => [1,2,-5,-3,nil], 
          "as.integer(NULL)" => [],
        }.each{|k, v|
          subject.eval("x<-#{k}")
          expect(subject.pull('x')).to eql(v)
        }
      end
      it "should pull an Array of Double" do
        subject.eval("x<-c(1.1,2.2,5,3,NA,NaN)") # auto-conversion to numeric vector
        expect(subject.pull('x')[0..-2]).to eql([1.1,2.2,5.0,3.0,nil])
        expect(subject.pull('x')[-1].nan?).to be_truthy
        
        subject.eval("x<-c(1L,2L,5L,3.0,NA,NaN)") # auto-conversion to numeric vector 
        expect(subject.pull('x')[0..-2]).to eql([1.0,2.0,5.0,3.0,nil])
        expect(subject.pull('x')[-1].nan?).to be_truthy
        
        subject.eval("x<-as.numeric(NULL)")
        expect(subject.pull('x')).to eql([])
      end
      it "should pull an Array of Logical" do
        {
          "c(T, F, NA)" => [true, false, nil], 
          "as.logical(NULL)" => [],
        }.each{|k, v|
          subject.eval("x<-#{k}")
          expect(subject.pull('x')).to eql(v)
        }
      end

      it "should pull a Matrix" do
        threshold = 1e-8
        [
          proc{ # integer matrix
            v = rand(100000000) # get 8 digits
            [v, "#{v}L"]
          },
          [ # double matrix
            proc{
              v = rand(100000000) # get 8 digits
              [Float("0.#{v}"), "0.#{v}"]
            },
            gen_matrix_cmp_per_elm_proc{|a, b|
              expect(a).to be_within(threshold).of(b)
            }
          ],
        ].each{|gen_proc, cmp_proc|
          nrow, ncol = [10, 10] # 10 x 10 small matrix
          subject.eval("x<-matrix(nrow=#{nrow}, ncol=#{ncol})")
          rx = Matrix[*((1..nrow).collect{|i|
            (1..ncol).collect{|j|
              v_rb, v_R = gen_proc.call
              subject.eval("x[#{i},#{j}]<-#{v_R}")
              v_rb
            }
          })]
          (cmp_proc || proc{|a, b| expect(a).to eql(b)}).call(subject.pull('x'), rx)
        }
      end
      
      it "should pull partially" do
        subject.eval("x<-c(1L,2L,-5L,-3L,NA)")
        [1,2,-5,-3,nil].each.with_index{|v, i|
          expect(subject.pull("x[[#{i + 1}]]")).to eql(v)
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
      it "should assign a Character" do
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
      it "should assign a Double" do
        [rand, 1 << 32, -(1 << 32)].each{|x|
          subject.assign("x", x)
          expect(subject.pull('x')).to eql(x.to_f)
        }
        subject.assign("x", Float::NAN)
        expect(subject.pull('x').nan?).to be_truthy
      end
      it "should assign a Logical" do
        [true, false, nil].each{|x|
          subject.assign("x", x)
          expect(subject.pull('x')).to eql(x)
        }
      end
      it "should assign an Array of Character" do
        x = ['a', 'b', nil]
        subject.assign("x", x)
        expect(subject.pull('x')).to eql(x)
      end
      it "should assign an Array of Integer" do
        x = [1, 2, -5, -3, nil]
        subject.assign("x", x)
        expect(subject.pull('x')).to eql(x)
      end
      it "should assign an Array of Double" do
        x = [rand(100000000), rand(0x1000) << 32, # Integer 
            rand, Rational(rand(1000), rand(1000) + 1), # Numeric except for Complex with available .to_f  
            nil, Float::NAN]
        subject.assign("x", x)
        expect(subject.pull('x')[0..-2]).to eql(x[0..-3].collect{|v| v.to_f} + [nil])
        expect(subject.pull('x')[-1].nan?).to be_truthy
      end
      it "should assign an Array of Logical" do
        x = [true, false, nil]
        subject.assign("x", x)
        expect(subject.pull('x')).to eql(x)
      end

      it "should assign a Matrix" do
        threshold = Float::EPSILON * 100
        [
          proc{rand(100000000)}, # integer matrix
          proc{v = rand(100000000); v > 50000000 ? nil : v}, # integer matrix with NA
          [ # double matrix
            proc{rand},
            gen_matrix_cmp_per_elm_proc{|a, b|
              expect(a).to be_within(threshold).of(b)
            },
          ],
          [ # double matrix with NA
            proc{v = rand; v > 0.5 ? nil : v},
            gen_matrix_cmp_per_elm_proc{|a, b|
              if b.kind_of?(Numeric) then
                expect(a).to be_within(threshold).of(b)
              else
                expect(a).to eql(nil)
              end
            },
          ],
        ].each{|gen_proc, cmp_proc|
          x = Matrix::build(100, 200){|i, j| gen_proc.call} # 100 x 200 matrix
          subject.assign("x", x)
          (cmp_proc || proc{|a, b| expect(a).to eql(b)}).call(subject.pull('x'), x)
        }        
      end
      
      it "should assign partially" do
        x = [1, 2, -5, -3, nil]
        subject.assign("x", x)
        expect(subject.pull('x')).to eql(x)
        subject.assign("x[[3]]", x[2] *= 10)
        expect(subject.pull('x')).to eql(x)
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
  
  describe "echo changes eval output" do
    let(:res){@res ||= {}}
    before(:each){
      allow(r).to receive(:puts){|str| res[str.to_sym] = true}
    }
    def check_output(*echo_args)
      r.echo(*echo_args)
      r.eval("write('out', stdout())")
      r.eval("write('err', stderr())")
      [:out, :err].collect{|k| res[k]} 
    end
    it "should output both stdout and stderr when echo(true, true)" do
      expect(check_output(true, true)).to eql([true, true])
    end
    it "should output stdout only when echo(true, false)" do
      expect(check_output(true, false)).to eql([true, nil])
    end
    it "should output nothing when echo(false)" do
      expect(check_output(false)).to eql([nil, nil])
    end
  end
  
  context "on eval in interactive mode" do
    let(:params){
      super().merge({:interactive => true})
    }
    it "should be interrupted by SIGINT" do
      if r.instance_variable_get(:@platform) =~ /java$/ then
        pending("JRuby does not give fully support for signal handling")
        fail
      end
      int_invoked = false
      int_handler = Signal::trap(:INT){int_invoked = true}
      printed = []
      eval_res = r.eval(<<-__TEXT__){|line|
        for(i in 1:10){
          print(i)
          Sys.sleep(1)
        }
      __TEXT__
        line =~ /^\[1\] *(\S+)/
        printed << Integer($1)
        Process::kill(:INT, $$) if (printed[-1] > 2)
      }
      Signal::trap(:INT, int_handler)
      expect(int_invoked).to be_truthy
      expect(eval_res).to be_falsy
      expect(printed).not_to include(10)
    end
  end
  
  context "on prompt" do
    let(:params){
      super().merge({:interactive => true})
    }
    let(:input){@input ||= []}
    before(:all){
      begin
        require 'readline' 
      rescue LoadError
      end
    }
    before(:each){
      allow(Readline).to receive(:readline){|prompt, add_hist|
        print(prompt)
        input.shift
      } if defined?(Readline)
      allow(r).to receive(:gets){input.shift}
      r.echo(true, true)
    }
    it "should exit with exit() input" do
      ['exit()', ' exit ( ) '].each{|str|
        input.replace([str])
        expect{r.prompt}.to output(/^> /).to_stdout
      }
    end
    it "should respond normally with correct inputs" do
      [
        [['1'], "> [1] 1"],
        [['1 +', '2'], "> + [1] 3"],
        [['1 +', '2 +', '3'], "> + + [1] 6"],
        [['a <- 1'], "> "],
        [['a <-', '1'], "> + "],
      ].each{|src, dst|
        input.replace(src + ['exit()'])
        expect{r.prompt}.to output(/^#{Regexp::escape(dst)}/).to_stdout
      }
    end
    it "should print error gently with incorrect inputs" do
      [
        ['1 +;'],
        ['a <-;'],
      ].each{|src|
        input.replace(src + ['exit()'])
        expect{r.prompt}.to output(/Unrecoverable parse error/).to_stdout
      }
    end
    it "should print R error gently" do
      if r.instance_variable_get(:@platform) =~ /(?!windows-)java$/ then
        pending("JRuby maybe fail due to stderr output handling")
      end
      [
        ['stop("something wrong!"); print("skip")', 'print("do other")'],
      ].each{|src|
        input.replace(src + ['exit()'])
        expect{r.prompt}.to output(/something wrong\!.*(?!skip).*do other/m).to_stdout
      }
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