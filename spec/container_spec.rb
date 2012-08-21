# -*- encoding : utf-8 -*-
require 'spec_helper'

def test_container(container, hash, uuid = nil)
  hash.reject { |k, v| k == :last_updated_at }.find do |k, v|
    container.send(k).should == v
  end

  container.last_updated_at.should == Time.at(hash['last_updated_at']) if hash['last_updated_at']
  container.uuid.should == uuid if uuid
end


describe SidekiqStatus::Container do
  let(:uuid) { "9a99fa87-0d95-47f4-87af-f381232e9f9d" }
  let(:status_key) { described_class.status_key(uuid) }
  let(:sample_json_hash) do
    {
        'status'          => "completed",
        'at'              => 50,
        'total'           => 200,
        'message'         => "Some message",
        'args'            => ['arg1', 'arg2'],
        'payload'         => {},
        'last_updated_at' => 1344855831
    }
  end

  specify ".status_key" do
    uuid = SecureRandom.uuid
    described_class.status_key(uuid).should == "sidekiq_status:#{uuid}"
  end

  specify ".kill_key" do
    described_class.kill_key.should == described_class::KILL_KEY
  end


  context "finders" do
    let!(:containers) do
      described_class::STATUS_NAMES.inject({}) do |accum, status_name|
        container = described_class.create('arg1')
        container.update_attributes(:status => status_name)

        accum[status_name] = container
        accum
      end
    end

    specify ".size" do
      described_class.size.should == containers.size
    end

    specify ".status_uuids" do
      expected = containers.values.map(&:uuid).map{ |uuid| [uuid, anything()] }
      described_class.status_uuids.should =~ expected
      described_class.status_uuids(0, 0).size.should == 1
    end

    specify ".statuses" do
      described_class.statuses.should be_all{|st| st.is_a?(described_class) }
      described_class.statuses.size.should == containers.size
      described_class.statuses(0, 0).size.should == 1
    end

    describe ".delete" do
      before do
        described_class.status_uuids.map(&:first).should =~ containers.values.map(&:uuid)
      end

      specify "deletes jobs in specific status" do
        statuses_to_delete = ['waiting', 'complete']
        described_class.delete(statuses_to_delete)

        described_class.status_uuids.map(&:first).should =~ containers.
            reject{ |status_name, container|  statuses_to_delete.include?(status_name) }.
            values.
            map(&:uuid)
      end

      specify "deletes jobs in all statuses" do
        described_class.delete()

        described_class.status_uuids.should be_empty
      end
    end
  end

  specify ".create" do
    SecureRandom.should_receive(:uuid).and_return(uuid)
    args = ['arg1', 'arg2', {arg3: 'val3'}]

    container = described_class.create(*args)
    container.should be_a(described_class)
    container.args.should == args

    # Check default values are set
    test_container(container, described_class::DEFAULTS.reject{|k, v| k == 'args' }, uuid)

    Sidekiq.redis do |conn|
      conn.exists(status_key).should be_true
    end
  end

  describe ".load" do
    it "raises StatusNotFound exception if status is missing in Redis" do
      expect { described_class.load(uuid) }.to raise_exception(described_class::StatusNotFound, uuid)
    end

    it "loads a container from the redis key" do
      json = MultiJson.dump(sample_json_hash)
      Sidekiq.redis { |conn| conn.set(status_key, json) }

      container = described_class.load(uuid)
      test_container(container, sample_json_hash, uuid)
    end

    it "cleans up unprocessed expired kill requests as well" do
      Sidekiq.redis do |conn|
        conn.zadd(described_class.kill_key, [
            [(Time.now - described_class.ttl - 1).to_i, 'a'],
            [(Time.now - described_class.ttl + 1).to_i, 'b'],
        ]
        )
      end

      json = MultiJson.dump(sample_json_hash)
      Sidekiq.redis { |conn| conn.set(status_key, json) }
      described_class.load(uuid)

      Sidekiq.redis do |conn|
        conn.zscore(described_class.kill_key, 'a').should be_nil
        conn.zscore(described_class.kill_key, 'b').should_not be_nil
      end
    end
  end

  specify "#dump" do
    hash = sample_json_hash.reject{ |k, v| k == 'last_updated_at' }
    container = described_class.new(uuid, hash)
    dump = container.dump
    dump.should == hash.merge('last_updated_at' => Time.now.to_i)
  end

  specify "#save saves container to Redis" do
    hash = sample_json_hash.reject{ |k, v| k == 'last_updated_at' }
    described_class.new(uuid, hash).save

    result = Sidekiq.redis{ |conn| conn.get(status_key) }
    result = MultiJson.load(result)

    result.should == hash.merge('last_updated_at' => Time.now.to_i)

    Sidekiq.redis{ |conn| conn.ttl(status_key).should >= 0 }
  end

  specify "#delete" do
    Sidekiq.redis do |conn|
      conn.set(status_key, "something")
      conn.zadd(described_class.kill_key, 0, uuid)
    end

    container = described_class.new(uuid)
    container.delete

    Sidekiq.redis do |conn|
      conn.exists(status_key).should be_false
      conn.zscore(described_class.kill_key, uuid).should be_nil
    end
  end

  specify "#request_kill, #should_kill?, #killable?" do
    container = described_class.new(uuid)
    container.should_kill?.should be_false
    container.should be_killable

    Sidekiq.redis do |conn|
      conn.zscore(described_class.kill_key, uuid).should be_nil
    end


    container.request_kill

    Sidekiq.redis do |conn|
      conn.zscore(described_class.kill_key, uuid).should == Time.now.to_i
    end
    container.should_kill?.should be_true
    container.should_not be_killable
  end

  specify "#kill" do
    container = described_class.new(uuid)
    container.request_kill
    Sidekiq.redis do |conn|
      conn.zscore(described_class.kill_key, uuid).should == Time.now.to_i
    end
    container.status.should_not == 'killed'


    container.kill

    Sidekiq.redis do |conn|
      conn.zscore(described_class.kill_key, uuid).should be_nil
    end

    container.status.should == 'killed'
    described_class.load(uuid).status.should == 'killed'
  end

  specify "#pct_complete" do
    container = described_class.new(uuid)
    container.at = 1
    container.total = 100
    container.pct_complete.should == 1

    container.at = 5
    container.total = 200
    container.pct_complete.should == 3 # 2.5.round(0) => 3
  end

  context "setters" do
    let(:container) { described_class.new(uuid) }

    describe "#at=" do
      it "sets numeric value" do
        container.total = 100
        container.at = 3
        container.at.should == 3
        container.total.should == 100
      end

      it "raises ArgumentError otherwise" do
        expect{ container.at = "Wrong" }.to raise_exception(ArgumentError)
      end

      it "adjusts total if its less than new at" do
        container.total = 200
        container.at = 250
        container.total.should == 250
      end
    end

    describe "#total=" do
      it "sets numeric value" do
        container.total = 50
        container.total.should == 50
      end

      it "raises ArgumentError otherwise" do
        expect{ container.total = "Wrong" }.to raise_exception(ArgumentError)
      end
    end

    describe "#status=" do
      described_class::STATUS_NAMES.each do |status|
        it "sets status #{status.inspect}" do
          container.status = status
          container.status.should == status
        end
      end

      it "raises ArgumentError otherwise" do
        expect{ container.status = 'Wrong' }.to raise_exception(ArgumentError)
      end
    end

    specify "#message=" do
      container.message = 'abcd'
      container.message.should == 'abcd'

      container.message = nil
      container.message.should be_nil

      message = double('Message', :to_s => 'to_s')
      container.message = message
      container.message.should == 'to_s'
    end

    specify "#payload=" do
      container.should respond_to(:payload=)
    end

    specify "update_attributes" do
      container.update_attributes(:at => 1, 'total' => 3, :message => 'msg', 'status' => 'working')
      reloaded_container = described_class.load(container.uuid)

      reloaded_container.at.should == 1
      reloaded_container.total.should == 3
      reloaded_container.message.should == 'msg'
      reloaded_container.status.should == 'working'

      expect{ container.update_attributes(:at => 'Invalid') }.to raise_exception(ArgumentError)
    end
  end
end