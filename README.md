# rinruby

Execute R code from Ruby.

* Forked from http://rinruby.ddahl.org/

### INSTALL

* gem install rootapp-rinruby

### USAGE


```ruby
require "rinruby"

R = RinRuby.new

n = 10
beta_0 = 1
beta_1 = 0.25
alpha = 0.05
seed = 23423
R.assign('x', (1..n).entries)
R.eval <<EOF
  set.seed(#{seed})
  y <- #{beta_0} + #{beta_1}*x + rnorm(#{n})
  fit <- lm( y ~ x )
  est <- round(coef(fit),3)
  pvalue <- summary(fit)$coefficients[2,4]
EOF
puts "E(y|x) ~= #{R.pull('est')[0]} + #{R.pull('est')[1]} * x"
if R.pull('pvalue') < alpha
  puts "Reject the null hypothesis and conclude that x and y are related."
else
  puts "There is insufficient evidence to conclude that x and y are related."
end
```

**Please note:**

The interface of RinRuby has slightly changed compared to the previous versions. 
Variables cannot be assigned directly anymore. But you need to use `assign(name, value)` to assign variables from the ruby side and `pull(name)` to retrieve assigned variables in R in Ruby. 

### REQUIREMENTS

* R

### LICENSE

GPL-3. See LICENSE.txt for more information.
