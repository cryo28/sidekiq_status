class TestWorker2
  include SidekiqStatus::Worker

  def perform(redis_key)
    signal = nil
    while signal != 'stop'
      signal = Sidekiq.redis{ |conn| conn.get(redis_key) }
      i = signal.to_i
      self.at(i, "Some message at #{i}")
      sleep(0.1)
    end
  end
end