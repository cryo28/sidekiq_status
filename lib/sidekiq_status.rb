# -*- encoding : utf-8 -*-
require 'sidekiq'

require 'securerandom'
require "sidekiq_status/version"
require "sidekiq_status/client_middleware"
require "sidekiq_status/container"
require "sidekiq_status/worker"
Sidekiq.client_middleware do |chain|
  chain.add SidekiqStatus::ClientMiddleware
end

require 'sidekiq_status/web' if defined?(Sidekiq::Web)