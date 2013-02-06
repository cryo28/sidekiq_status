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

  describe ".perform_async" do
    it "invokes middleware which creates sidekiq_status container with the same jid" do
      jid = SomeWorker.perform_async(*args)
      jid.should be_a(String)

      container = SidekiqStatus::Container.load(jid)
      container.args.should == args
    end
  end

  describe "#perform (Worker context)" do
    let(:worker) { SomeWorker.new }

    it "receives jid as parameters, loads container and runs original perform with enqueued args" do
      worker.should_receive(:some_method).with(*args)
      jid = SomeWorker.perform_async(*args)
      worker.perform(jid)
    end

    it "changes status to working" do
      has_been_run = false
      worker.extend(Module.new do
        define_method(:some_method) do |*args|
          status_container.status.should == 'working'
          has_been_run = true
        end
      end)

      jid = SomeWorker.perform_async(*args)
      worker.perform(jid)

      has_been_run.should be_true
      worker.status_container.reload.status.should == 'complete'
    end

    it "intercepts failures and set status to 'failed' then re-raises the exception" do
      exc = RuntimeError.new('Some error')
      worker.stub(:some_method).and_raise(exc)

      jid = SomeWorker.perform_async(*args)

      expect{ worker.perform(jid) }.to raise_exception(exc)

      container = SidekiqStatus::Container.load(jid)
      container.status.should == 'failed'
    end

    it "sets status to 'complete' if finishes without errors" do
      jid = SomeWorker.perform_async(*args)
      worker.perform(jid)

      container = SidekiqStatus::Container.load(jid)
      container.status.should == 'complete'
    end

    it "handles kill requests if kill requested before job execution" do
      jid = SomeWorker.perform_async(*args)
      container = SidekiqStatus::Container.load(jid)
      container.request_kill

      worker.perform(jid)

      container.reload
      container.status.should == 'killed'
    end

    it "handles kill requests if kill requested amid job execution" do
      jid = SomeWorker.perform_async(*args)
      container = SidekiqStatus::Container.load(jid)
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

      worker_thread = Thread.new{ worker.perform(jid) }


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
      jid = SomeWorker.perform_async(*args)
      container = SidekiqStatus::Container.load(jid)

      lets_stop = false

      worker.extend(Module.new do
        define_method(:some_method) do |*args|
          self.total=(200)
          self.at(50, "25% done")
          self.payload = 'some payload'
          wait{ lets_stop }
        end
      end)

      worker_thread = Thread.new{ worker.perform(jid) }
      checker_thread = Thread.new do
        wait{ container.reload.working? }
        container.at.should      == 50
        container.total.should   == 200
        container.message.should == '25% done'
        container.payload        == 'some payload'

        lets_stop = true
      end

      worker_thread.join(15)
      checker_thread.join(15)

      wait{ container.reload.complete? }

      container.payload.should == 'some payload'
      container.message.should be_nil
    end
  end
end
