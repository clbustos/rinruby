require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
puts "RinRuby #{RinRuby::VERSION} specification"

R = RinRuby.new

describe RinRuby do
  describe "on init" do
    it "should accept parameters as specified on Dahl & Crawford(2009)" do
      r = RinRuby.new(false, "R", 38500, 1)

      expect(r.echo_enabled).to be(false)
      expect(r.executable).to eq("R")
      expect(r.port_number).to eq(38500)
      expect(r.port_width).to eq(1)
    end

    it "should accept :echo parameters" do
      r = RinRuby.new(:echo => false)
      expect(r.echo_enabled).to be(false)
    end

    it "should accept :port_number" do
      port = 38442 + rand(3)
      r = RinRuby.new(:port_number => port, :port_width => 1)
      expect(r.port_number).to eq(port)
      r.quit
    end

    it "should accept :port_width" do
      port = 38442
      port_width = rand(10) + 1
      r = RinRuby.new(:port => port, :port_width => port_width)

      expect(r.port_width).to eq(port_width)
      expect(r.port_number).to satisfy { |v| v >= port && v < port + port_width }
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
      expect(R.eval("x <- 1")).to be(true)
    end

    it "return false for complete? for incorrect expressions" do
      expect(R.complete?("x <-")).to be(false)
    end

    it "correct eval should return true" do
      expect(R.complete?("x <- 1")).to be(true)
    end

    it "incorrect eval should raise an ParseError" do
      expect do
        R.eval("x <-")
      end.to raise_error(RinRuby::ParseError)
    end
  end

  context "on assign" do
    it "should assign correctly" do
      x = rand
      R.assign("x", x)
      expect(R.pull("x")).to eq(x)
    end
  end

  context "on pull" do
    it "should pull a String" do
      R.eval("x <- 'Value'")
      expect(R.pull("x")).to eq("Value")
    end

    it "should pull an Integer" do
      R.eval("x <- 1")
      expect(R.pull("x")).to eq(1)
    end

    it "should pull a Float" do
      R.eval("x <- 1.5")
      expect(R.pull("x")).to eq(1.5)
    end

    it "should pull an Array of Numeric" do
      R.eval("x <- c(1,2.5,3)")
      expect(R.pull("x")).to eq([1, 2.5, 3])
    end

    it "should pull an Array of strings" do
      R.eval("x <- c('a', 'b')")
      expect(R.pull("x")).to eq(["a", "b"])
    end

    it "should push a Matrix" do
      matrix = Matrix[
        [rand, rand, rand],
        [rand, rand, rand]
      ]

      R.assign('x', matrix)
      pulled_matrix = R.pull("x")

      matrix.row_size.times do |i|
        matrix.column_size.times do |j|
          expect(matrix[i,j]).to be_within(1e-10).of(pulled_matrix[i,j])
        end
      end
    end

    it "raises UndefinedVariableError if pulling variable that is undefined" do
      expect do
        R.pull("miss")
      end.to raise_error(RinRuby::UndefinedVariableError)
    end

    it "raises error message if trying to pull a type that cannot be sent over wire" do
      expect do
        R.pull("typeof")
      end.to raise_error(RinRuby::UnsupportedTypeError, "Unsupported R data type 'function closure  '")
    end
  end

  context "on quit" do
    before(:each) do
      @r = RinRuby.new(:echo => false)
    end

    it "return true" do
      expect(@r.quit).to be(true)
    end

    it "returns an error if used again" do
      @r.quit
      expect do
        @r.eval("x = 1")
      end.to raise_error(RinRuby::EngineClosed)
    end
  end
end
