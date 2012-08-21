require 'spec_helper'

describe Sidekiq::Worker do
  class SomeWorker
    include SidekiqStatus::Worker

    def perform(*args)
      some_method(*args)
    end

    def some_method(*args); end
  end

  let(:args) { ['arg1', 'arg2', {'arg3' => 'val3'}]}

  describe ".perform_async (Client context)" do
    it "pushes a new job to queue and returns its uuid" do
      uuid = SomeWorker.perform_async(*args)
      uuid.should be_a(String)

      container = SidekiqStatus::Container.load(uuid)
      container.args.should == args
    end

    it "proxies the #perform_async call to Sidekiq::Worker with uuid as only argument" do
      uuid = SecureRandom.uuid
      SecureRandom.stub(:uuid).and_return(uuid)

      SomeWorker.should_receive(:client_push) do |client_push_args|
        enqueued_args = client_push_args['args']
        enqueued_args.should == [uuid]
      end

      SomeWorker.perform_async(*args)
    end

    it "returns false and deletes container from redis if some middleware rejects job" do
      Sidekiq.redis{ |conn| conn.zcard(SidekiqStatus::Container.statuses_key).should == 0 }
      Sidekiq::Client.should_receive(:push).and_return(false)

      uuid = SomeWorker.perform_async(*args)
      uuid.should be_false

      Sidekiq.redis{ |conn| conn.zcard(SidekiqStatus::Container.statuses_key).should == 0 }
    end
  end

  describe "#perform (Worker context)" do
    let(:worker) { SomeWorker.new }

    it "receives uuid as parameters, loads container and runs original perform with enqueued args" do
      worker.should_receive(:some_method).with(*args)
      uuid = SomeWorker.perform_async(*args)
      worker.perform(uuid)
    end

    it "changes status to working" do
      has_been_run = false
      worker.extend(Module.new do
        define_method(:some_method) do |*args|
          status_container.status.should == 'working'
          has_been_run = true
        end
      end)

      uuid = SomeWorker.perform_async(*args)
      worker.perform(uuid)

      has_been_run.should be_true
      worker.status_container.reload.status.should == 'complete'
    end

    it "intercepts failures and set status to 'failed' then re-raises the exception" do
      exc = RuntimeError.new('Some error')
      worker.stub(:some_method).and_raise(exc)

      uuid = SomeWorker.perform_async(*args)

      expect{ worker.perform(uuid) }.to raise_exception(exc)

      container = SidekiqStatus::Container.load(uuid)
      container.status.should == 'failed'
    end

    it "sets status to 'complete' if finishes without errors" do
      uuid = SomeWorker.perform_async(*args)
      worker.perform(uuid)

      container = SidekiqStatus::Container.load(uuid)
      container.status.should == 'complete'
    end

    it "handles kill requests if kill requested before job execution" do
      uuid = SomeWorker.perform_async(*args)
      container = SidekiqStatus::Container.load(uuid)
      container.request_kill

      worker.perform(uuid)

      container.reload
      container.status.should == 'killed'
    end

    it "handles kill requests if kill requested amid job execution" do
      uuid = SomeWorker.perform_async(*args)
      container = SidekiqStatus::Container.load(uuid)
      container.status.should == 'waiting'

      i = 0
      i_mut = Mutex.new

      worker.extend(Module.new do
        define_method(:some_method) do |*args|
          loop do
            i_mut.synchronize do
              i += 1
            end

            status_container.at = i
          end
        end
      end)

      worker_thread = Thread.new{ worker.perform(uuid) }


      killer_thread = Thread.new do
        sleep(0.01) while i < 100
        container.reload.status.should == 'working'
        container.request_kill
      end

      worker_thread.join(2)
      killer_thread.join(1)

      container.reload
      container.status.should == 'killed'
      container.at.should >= 100
    end

    it "allows to set at, total and customer payload from the worker" do
      uuid = SomeWorker.perform_async(*args)
      container = SidekiqStatus::Container.load(uuid)

      ready = false
      lets_stop = false

      worker.extend(Module.new do
        define_method(:some_method) do |*args|
          self.total=(200)
          self.at(50, "25% done")
          self.payload = 'some payload'
          ready = true
          sleep(0.01) unless lets_stop
        end
      end)

      worker_thread = Thread.new{ worker.perform(uuid) }
      checker_thread = Thread.new do
        sleep(0.01) unless ready

        container.reload
        container.status.should  == 'working'
        container.at.should      == 50
        container.total.should   == 200
        container.message.should == '25% done'
        container.payload        == 'some payload'

        lets_stop = true
      end

      worker_thread.join(10)
      checker_thread.join(10)

      container.reload
      container.status.should  == 'complete'
      container.payload.should == 'some payload'
      container.message.should be_nil
    end
  end
end