# -*- encoding: utf-8 -*-
require File.expand_path('../lib/sidekiq_status/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Artem Ignatyev"]
  gem.email         = ["cryo28@gmail.com"]
  gem.description   = "Job status tracking extension for Sidekiq"
  gem.summary       = "A Sidekiq extension to track job execution statuses and return job results back to the client in a convenient manner"
  gem.homepage      = "https://github.com/cryo28/sidekiq_status"
  gem.licenses      = ["MIT"]

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "sidekiq_status"
  gem.require_paths = ["lib"]
  gem.version       = SidekiqStatus::VERSION

  gem.add_runtime_dependency("sidekiq", ">= 2.4", "< 3.0")

  gem.add_development_dependency("activesupport")
  gem.add_development_dependency("rspec")
  gem.add_development_dependency("simplecov")
  gem.add_development_dependency("rake")
  gem.add_development_dependency("timecop")

  gem.add_development_dependency("yard")
  gem.add_development_dependency("maruku")
end
