# -*- encoding : utf-8 -*-
require 'sidekiq'

require 'securerandom'
require "sidekiq_status/version"
require "sidekiq_status/container"
require "sidekiq_status/worker"



#require 'sidekiq_status/web' if defined?(Sidekiq::Web)