= rinruby

* http://rinruby.ddahl.org/

== DESCRIPTION:

RinRuby is a Ruby library that integrates the R interpreter in Ruby, making R's statistical routines and graphics available within Ruby.  The library consists of a single Ruby script that is simple to install and does not require any special compilation or installation of R.  Since the library is 100% pure Ruby, it works on a variety of operating systems, Ruby implementations, and versions of R.  RinRuby's methods are simple, making for readable code.  The {website [rinruby.ddahl.org]}[http://rinruby.ddahl.org] describes RinRuby usage, provides comprehensive documentation, gives several examples, and discusses RinRuby's implementation.


Copyright 2005-2008 David B. Dahl

Developed by David B. Dahl
Documented by David B. Dahl and Scott Crawford
Homepage: http://rinruby.ddahl.org

Contributors: Claudio Bustos

== FEATURES/PROBLEMS:

* Pure Ruby. Works on Ruby 1.8.7, 1.9 and JRuby 1.4
* Slower than RSRuby, but more robust

== SYNOPSIS:
Below is a simple example of RinRuby usage for simple linear regression. The simulation parameters are defined in Ruby, computations are performed in R, and Ruby reports the results. In a more elaborate application, the simulation parameter might come from input from a graphical user interface, the statistical analysis might be more involved, and the results might be an HTML page or PDF report. 

<b>Code</b>:

      require "rinruby"
      n = 10
      beta_0 = 1
      beta_1 = 0.25
      alpha = 0.05
      seed = 23423
      R.x = (1..n).entries
      R.eval <<EOF
          set.seed({seed})
          y <- {beta_0} + {beta_1}*x + rnorm({n})
          fit <- lm( y ~ x )
          est <- round(coef(fit),3)
          pvalue <- summary(fit)$coefficients[2,4]
      EOF
      puts "E(y|x) ~= {R.est[0]} + {R.est[1]} * x"
      if R.pvalue < alpha
        puts "Reject the null hypothesis and conclude that x and y are related."
      else
        puts "There is insufficient evidence to conclude that x and y are related."
      end

<b>Output</b>:

      E(y|x) ~= 1.264 + 0.273 * x
      Reject the null hypothesis and conclude that x and y are related.

== REQUIREMENTS:

* R

== INSTALL:

* sudo gem install rinruby


== LICENSE:

GPL-3. See LICENSE.txt for more information.

