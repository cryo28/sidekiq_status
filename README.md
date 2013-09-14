# SidekiqStatus

[![Build Status](https://travis-ci.org/cryo28/sidekiq_status.png?branch=master)](https://travis-ci.org/cryo28/sidekiq_status)
[![Dependency Status](https://gemnasium.com/cryo28/sidekiq_status.png)](https://gemnasium.com/cryo28/sidekiq_status)
[![Test coverage](https://coveralls.io/repos/cryo28/sidekiq_status/badge.png?branch=master)](https://coveralls.io/r/cryo28/sidekiq_status)

Sidekiq extension to track job execution statuses and returning job results back to the client in a convenient manner

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'sidekiq_status'
```

And then execute:

    $ bundle

## Usage

### Basic

Create a status-friendly worker by include SidekiqStatus::Worker module having #perform method with Sidekiq worker-compatible signature:

```ruby
class MyWorker
   include SidekiqStatus::Worker

   def perform(arg1, arg2)
      # do something
   end
end
```

Now you can enqueue some jobs for this worker

```ruby
jid = MyWorker.perform_async('val_for_arg1', 'val_for_arg2')
```

If a job is rejected by some Client middleware, #perform_async returns false (as it does with ordinary Sidekiq worker).

Now, you can easily track the status of the job execution:

```ruby
status_container = SidekiqStatus::Container.load(jid)
status_container.status # => 'waiting'
```

When a jobs is scheduled its status is *waiting*. As soon sidekiq worker begins job execution its status is changed to *working*.
If the job successfully finishes (i.e. doesn't raise an unhandled exception) its status is *complete*. Otherwise its status is *failed*.

### Communication from Worker to Client

*SidekiqStatus::Container* has some attributes and *SidekiqStatus::Worker* module extends your Worker class with a few methods which allow Worker to leave
some info for the subsequent fetch by a Client. For example you can notify client of the worker progress via *at* and *total=* methods

```ruby
class MyWorker
   include SidekiqStatus::Worker

   def perform(arg1, arg2)
      objects = Array.new(200) { 'some_object_to_process' }
      self.total= objects.count
      objects.each_with_index do |object, index|
        at(index, "Processing object #{index}")
        object.process!
      end
   end
end
```

Lets presume a client refreshes container at the middle of job execution (when it's processing the object number 50):

```ruby
container = SidekiqStatus::Container.load(jid) # or container.reload

container.status       # => 'working'
container.at           # => 50
container.total        # => 200
container.pct_complete # => 25
container.message      # => 'Processing object #{50}'
```

Also, a job can leave for the client any custom payload. The only requirement is json-serializeability

```ruby
class MyWorker
   include SidekiqStatus::Worker

   def perform(arg1, arg2)
      objects = Array.new(5) { |i| i }
      self.total= objects.count
      result = objects.inject([]) do |accum, object|
        accum << "result #{object}"
        accum
      end

      self.payload= result
   end
end
```


Then a client can fetch the result payload

```ruby
container = SidekiqStatus::Container.load(jid)
container.status  # => 'complete'
container.payload # => ["result 0", "result 1", "result 2", "result 3", "result 4"]
```

SidekiqStatus stores all container attributes in a separate redis key until it's explicitly deleted via container.delete method
or until redis key expires (see SidekiqStatus::Container.ttl class_attribute).

### Job kill

Any job which is waiting or working can be killed. A working job is killed at the moment of container access.

```ruby
container = SidekiqStatus::Container.load(jid)
container.status # => 'working'
container.killable? # => true
container.should_kill # => false

container.request_kill

container.status # => 'working'
container.killable? # => false
container.should_kill # => true

sleep(1)

container.reload
container.status # => 'killed'
```

### Sidekiq web integration

SidekiqStatus also provides an extension to Sidekiq web interface with /statuses page where you can track and kill jobs
and clean status containers.

   1. Setup Sidekiq web interface according to Sidekiq documentation
   2. Add "require 'sidekiq_status/web'" beneath "require 'sidekiq/web'"

## Changelog

### 1.0.5

   * Sidekiq 2.14 support
   * Do not create (and display in sidekiq_status/web) status containers
     for the jobs scheduled to run in the future
     by the means of perform_at/perform_in (mhfs)
   * Sidekiq web templates converted from .slim to .erb
   * Allow specifying worker name as a String (gumayunov)
   * Added ruby 2.0 to travis build matrix
   * Don't be too smart in extending Sinatra template search path (springbok)
   * Show worker names and adjust sidekiq-web template tags to conform 
     to Sidekiq conventions (mhfs)

### 1.0.4

   * Sidekiq 2.10 and 2.11 support  

### 1.0.3

   * Include SidekiqStatus::Web app into Sidekiq::Web app unobtrusively (pdf)
   * sidekiq 2.8.0 and 2.9.0 support

### 1.0.2

   * sidekiq 2.7.0 support
   * sidekiq integration tests
   * Display progress bar and last message in sidekiq-web tab (leandrocg)
 
### 1.0.1

   * sidekiq 2.6.x support

### 1.0.0

   * First release

## Roadmap

   * Add some sidekiq-web specs
   * Support running inline with sidekiq/testing

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Don't forget to write specs. Make sure rake spec passes
4. Commit your changes (`git commit -am 'Added some feature'`)
5. Push to the branch (`git push origin my-new-feature`)
6. Create new Pull Request

## Copyright

SidekiqStatus © 2012-2013 by Artem Ignatyev. SidekiqStatus is licensed under the MIT license

