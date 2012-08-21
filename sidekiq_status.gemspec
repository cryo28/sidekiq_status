# -*- encoding: utf-8 -*-
require File.expand_path('../lib/sidekiq_status/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Artem Ignatyev"]
  gem.email         = ["cryo28@gmail.com"]
  gem.description   = %q{TODO: Write a gem description}
  gem.summary       = %q{TODO: Write a gem summary}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "sidekiq_status"
  gem.require_paths = ["lib"]
  gem.version       = SidekiqStatus::VERSION

  gem.add_runtime_dependency("sidekiq", "~> 2.1.1")

  gem.add_development_dependency("rspec")
  gem.add_development_dependency("simplecov")
  gem.add_development_dependency("rake")
  gem.add_development_dependency("timecop")

  gem.add_development_dependency("rdiscount")
  gem.add_development_dependency("yard")
end
