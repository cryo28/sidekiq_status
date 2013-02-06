require 'spec_helper'

describe SidekiqStatus::Worker do
  def run_sidekiq(show_sidekiq_output = ENV['SHOW_SIDEKIQ'])
    log_to = show_sidekiq_output ? STDOUT : GEM_ROOT.join('log/spawned_sidekiq.log').to_s
    command = 'bundle exec sidekiq -r ./boot.rb --concurrency 1'

    Process.spawn(
      command,
      :chdir => DUMMY_APP_ROOT,
      :err => :out,
      :out => log_to,
      :pgroup => true
    )
  end

  def with_sidekiq_running
    pid = run_sidekiq

    begin
      yield(pid)
    ensure
      Process.kill('TERM', -Process.getpgid(pid))
      Process.wait(pid)
    end
  end

  context "integrates seamlessly with sidekiq and" do
    it "allows to query for complete job status and request payload" do
      some_value = 'some_value'
      jid = TestWorker1.perform_async(some_value)
      container = SidekiqStatus::Container.load(jid)
      container.should be_waiting

      with_sidekiq_running do
        wait{ container.reload.complete? }

        container.total.should == 200
        container.payload.should == some_value
      end
    end

    it "allows to query for working job status and request payload" do
      redis_key = 'SomeRedisKey'

      jid = TestWorker2.perform_async(redis_key)
      container = SidekiqStatus::Container.load(jid)
      container.should be_waiting

      with_sidekiq_running do
        wait{ container.reload.working? }

        Sidekiq.redis{ |conn| conn.set(redis_key, 10) }
        wait{  container.reload.at == 10 }
        container.message.should == 'Some message at 10'

        Sidekiq.redis{ |conn| conn.set(redis_key, 50) }
        wait{ container.reload.at == 50 }
        container.message.should == 'Some message at 50'

        Sidekiq.redis{ |conn| conn.set(redis_key, 'stop') }
        wait{ container.reload.complete? }
        container.should be_complete
        container.message.should be_nil
      end
    end
  end
end
