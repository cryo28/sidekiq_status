# -*- encoding : utf-8 -*-
module SidekiqStatus
  class Container
    class StatusNotFound < RuntimeError; end

    STATUS_NAMES = %w(waiting working complete failed killed).freeze

    FINISHED_STATUS_NAMES = %w(complete failed killed)

    KILL_KEY = 'sidekiq_status_kill'.freeze

    STATUSES_KEY = 'sidekiq_statuses'.freeze

    class_attribute :ttl
    self.ttl = 60*60*24*30 # 30 days

    DEFAULTS = {
        'args'    => [],
        'status'  => 'waiting',
        'at'      => 0,
        'total'   => 100,
        'message' => nil,
        'payload' => {}
    }.freeze

    attr_reader :uuid
    attr_reader :args, :status, :at, :total, :message, :last_updated_at
    attr_accessor :payload

    def self.status_key(uuid)
      "sidekiq_status:#{uuid}"
    end

    def self.statuses_key
      STATUSES_KEY
    end

    def self.kill_key
      KILL_KEY
    end

    def self.delete(status_names = nil)
      status_names ||= STATUS_NAMES
      status_names = [status_names] unless status_names.is_a?(Array)

      self.statuses.select{ |container| status_names.include?(container.status) }.map(&:delete)
    end

    def self.status_uuids(start = 0, stop = -1)
      Sidekiq.redis do |conn|
        conn.zrange(self.statuses_key, start, stop, :with_scores => true)
      end
    end

    def self.statuses(start = 0, stop = -1)
      uuids = status_uuids(start, stop)
      uuids.map!{ |uuid, score| uuid }
      load_multi(uuids)
    end

    def self.size
      Sidekiq.redis do |conn|
        conn.zcard(self.statuses_key)
      end
    end

    def self.create(*args)
      new(SecureRandom.uuid, 'args' => args).tap(&:save)
    end

    def self.load(uuid)
      data = load_data(uuid)
      new(uuid, data)
    end

    def self.load_multi(uuids)
      data = load_data_multi(uuids)
      data.map do |uuid, data|
        new(uuid, data)
      end
    end

    def self.load_data(uuid)
      load_data_multi([uuid])[uuid] or raise StatusNotFound.new(uuid.to_s)
    end

    def self.load_data_multi(uuids)
      keys = uuids.map{ |uuid| status_key(uuid) }

      return {} if keys.empty?

      threshold = Time.now - self.ttl

      data = Sidekiq.redis do |conn|
        conn.multi do
          conn.mget(*keys)

          conn.zremrangebyscore(kill_key, 0, threshold.to_i)     # Clean up expired unprocessed kill requests
          conn.zremrangebyscore(statuses_key, 0, threshold.to_i) # Clean up expired statuses from statuses sorted set
        end
      end

      data = data.first.map do |json|
        json ? Sidekiq.load_json(json) : nil
      end

      Hash[uuids.zip(data)]
    end

    def initialize(uuid, data = {})
      @uuid = uuid
      load(data)
    end

    def load(data)
      data                                  = DEFAULTS.merge(data)
      @args, @status, @at, @total, @message = data.values_at('args', 'status', 'at', 'total', 'message')
      @payload                              = data['payload']
      @last_updated_at                      = data['last_updated_at'] && Time.at(data['last_updated_at'].to_i)
    end

    def dump
      {
          'status'          => self.status,
          'at'              => self.at,
          'total'           => self.total,
          'message'         => self.message,
          'args'            => self.args,
          'payload'         => self.payload,
          'last_updated_at' => Time.now.to_i
      }
    end

    def reload
      data = self.class.load_data(uuid)
      load(data)
      self
    end

    def status_key
      self.class.status_key(uuid)
    end

    def save
      data = dump
      data = Sidekiq.dump_json(data)

      Sidekiq.redis do |conn|
        conn.multi do
          conn.setex(status_key, self.ttl, data)
          conn.zadd(self.class.statuses_key, Time.now.to_f.to_s, self.uuid)
        end
      end
    end

    def delete
      Sidekiq.redis do |conn|
        conn.multi do
          conn.del(status_key)

          conn.zrem(self.class.kill_key, self.uuid)
          conn.zrem(self.class.statuses_key, self.uuid)
        end
      end
    end

    def request_kill
      Sidekiq.redis do |conn|
        conn.zadd(self.class.kill_key, Time.now.to_f.to_s, self.uuid)
      end
    end

    def kill_requested?
      Sidekiq.redis do |conn|
        conn.zrank(self.class.kill_key, self.uuid)
      end
    end

    def kill
      self.status = 'killed'

      Sidekiq.redis do |conn|
        conn.multi do
          save
          conn.zrem(self.class.kill_key, self.uuid)
        end
      end
    end

    def killable?
      !kill_requested? && %w(waiting working).include?(self.status)
    end

    def pct_complete
      (at.to_f / total * 100).round
    end

    def at=(at)
      raise ArgumentError, "at=#{at.inspect} is not a scalar number" unless at.is_a?(Numeric)
      @at = at
      @total = @at if @total < @at
    end

    def total=(total)
      raise ArgumentError, "total=#{total.inspect} is not a scalar number" unless total.is_a?(Numeric)
      @total = total
    end

    def status=(status)
      raise ArgumentError, "invalid status #{status.inspect}" unless STATUS_NAMES.include?(status)
      @status = status
    end

    def message=(message)
      @message = message && message.to_s
    end

    def attributes=(attrs = {})
      attrs.each do |attr_name, value|
        setter = "#{attr_name}="
        send(setter, value)
      end
    end

    def update_attributes(attrs = {})
      self.attributes = attrs
      save
    end

    STATUS_NAMES.each do |status_name|
      define_method("#{status_name}?") do
        status == status_name
      end
    end
  end
end

