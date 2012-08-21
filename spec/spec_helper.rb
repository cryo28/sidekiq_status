# -*- encoding : utf-8 -*-
require 'bundler'
Bundler.setup

ENV['RACK_ENV'] = ENV['RAILS_ENV'] = 'test'

require 'simplecov'
SimpleCov.start

#require 'sidekiq'

require 'sidekiq_status'
require 'sidekiq/util'

require 'timecop'

Sidekiq.logger.level = Logger::ERROR

require 'sidekiq/redis_connection'
REDIS = Sidekiq::RedisConnection.create(:url => "redis://localhost/15", :namespace => 'test', :size => 1)

RSpec.configure do |c|
  c.before do
    Sidekiq.redis = REDIS
    Sidekiq.redis{ |conn| conn.flushdb }
  end

  c.around do |example|
    Timecop.freeze(Time.utc(2012)) do
      example.call
    end
  end
end
