# -*- encoding : utf-8 -*-

module SidekiqStatus
  class ClientMiddleware
    def call(worker, item, queue)
      worker = worker.constantize if worker.is_a?(String)
      return yield unless worker < SidekiqStatus::Worker

      # Don't start reporting status if the job is scheduled for the future
      return yield if item['at']

      jid  = item['jid']
      args = item['args']
      item['args'] = [jid]

      SidekiqStatus::Container.create(
          'jid'    => jid,
          'worker' => worker.name,
          'queue'  => queue,
          'args'   => args
      )

      yield
    rescue Exception => exc
      SidekiqStatus::Container.load(jid).delete rescue nil
      raise exc
    end
  end
end
