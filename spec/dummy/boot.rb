require 'rubygems'
require 'bundler'
Bundler.require

require 'active_support/dependencies'

DUMMY_APP_ROOT = Pathname.new(File.expand_path('../', __FILE__))
Sidekiq.redis = {:url => "redis://localhost/15", :size => 5}

ActiveSupport::Dependencies.autoload_paths += Dir.glob(DUMMY_APP_ROOT.join('app/*'))





