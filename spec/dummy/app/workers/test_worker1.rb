class TestWorker1
  include SidekiqStatus::Worker

  def perform(arg1)
    self.payload = arg1
    self.total   = 200
  end
end