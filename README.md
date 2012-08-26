# SidekiqStatus

Sidekiq extension to track job execution statuses and returning job results back to the client in a convenient manner

## Installation

Add this line to your application's Gemfile:

    gem 'sidekiq_status'

And then execute:

    $ bundle

## Usage

### Basic

Create a status-friendly worker by include SidekiqStatus::Worker module having #perform method with Sidekiq worker-compatible signature:

    class MyWorker
       include SidekiqStatus::Worker

       def perform(arg1, arg2)
          # do something
       end
    end

Now you can enqueue some jobs for this worker

    uuid = MyWorker.perform_async('val_for_arg1', 'val_for_arg2')

If a job is rejected by some Client middleware, #perform_async returns false (as it doesn with ordinary Sidekiq worker).

Now, you can easily track the status of the job execution:

     status_container = SidekiqStatus::Container.load(uuid)
     status_container.status # => 'waiting'

When a jobs is scheduled its status is *waiting*. As soon sidekiq worker begins job execution its status is changed to *working*.
If the job successfully finishes (i.e. doesn't raise an unhandled exception) its status is *complete*. Otherwise its status is *failed*.

### Communication from Worker to Client

*SidekiqStatus::Container* has some attributes and *SidekiqStatus::Worker* module extends your Worker class with a few methods which allow Worker to leave
some info for the subsequent fetch by a Client. For example you can notify client of the worker progress via *at* and *total=* methods

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

Lets presume a client refreshes container at the middle of job execution (when it's processing the object number 50):

    container = SidekiqStatus::Container.load(uuid) # or container.reload

    container.status       # => 'working'
    container.at           # => 50
    container.total        # => 200
    container.pct_complete # => 25
    container.message      # => 'Processing object #{50}'

Also, a job can leave for the client any custom payload. The only requirement is json-serializeability

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


Then a client can fetch the result payload

   container = SidekiqStatus::Container.load(uuid)
   container.status  # => 'complete'
   container.payload # => ["result 0", "result 1", "result 2", "result 3", "result 4"]

SidekiqStatus stores all container attributes in a separate redis key until it's explicitly deleted via container.delete method
or until redis key expires (see SidekiqStatus::Container.ttl class_attribute).

### Job kill

Any job which is waiting or working can be killed. A working job is killed at the moment of container access.

    container = SidekiqStatus::Container.load(uuid)
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

### Sidekiq web integration

SidekiqStatus also provides an extension to Sidekiq web interface with /statuses page where you can track and kill jobs
and clean status containers.

   1. Setup Sidekiq web interface according to Sidekiq documentation
   2. Add "require 'sidekiq_status/web'" beneath "reqyure 'sidekiq/web'"

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request


## Copyright

SidekiqStatus © 2012 by Artem Ignatyev. SidekiqStatus is licensed under the MIT license

