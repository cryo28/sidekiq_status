source 'https://rubygems.org'

# Specify your gem's dependencies in sidekiq_status.gemspec
gemspec

gem 'sidekiq', ENV['SIDEKIQ_VERSION'] if ENV['SIDEKIQ_VERSION']
gem 'activesupport', '< 4.0.0' if RUBY_VERSION < '1.9.3'
gem 'coveralls', require: false

