# -*- encoding : utf-8 -*-
require 'bundler'
Bundler.setup
ENV['RACK_ENV'] = ENV['RAILS_ENV'] = 'test'
GEM_ROOT = Pathname.new(File.expand_path('../..', __FILE__))


require 'simplecov'
SimpleCov.start do
  root GEM_ROOT
end

require 'coveralls'
Coveralls.wear!

require 'rspec/its'
require 'sidekiq_status'
require 'sidekiq/util'

require 'timecop'

Sidekiq.logger.level = Logger::ERROR


require GEM_ROOT.join('spec/dummy/boot.rb')

RSpec.configure do |c|
  c.expect_with :rspec do |expectations|
    expectations.syntax = [:should, :expect]
  end

  c.before do
    Sidekiq.redis{ |conn| conn.flushdb }
  end

  c.around do |example|
    Timecop.freeze(Time.utc(2012)) do
      example.call
    end
  end

  def wait(&block)
    Timeout.timeout(15) do
      sleep(0.5) while !block.call
    end
  end
end
