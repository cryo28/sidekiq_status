# -*- encoding : utf-8 -*-
require 'spec_helper'

def test_container(container, hash, jid = nil)
  hash.reject { |k, v| k == :last_updated_at }.find do |k, v|
    container.send(k).should == v
  end

  container.last_updated_at.should == Time.at(hash['last_updated_at']) if hash['last_updated_at']
  container.jid.should == jid if jid
end


describe SidekiqStatus::Container do
  let(:jid) { "c2db8b1b460608fb32d76b7a" }
  let(:status_key) { described_class.status_key(jid) }
  let(:sample_json_hash) do
    {
        'args'            => ['arg1', 'arg2'],
        'worker'          => 'SidekiqStatus::Worker',
        'queue'           => '',

        'status'          => "completed",
        'at'              => 50,
        'total'           => 200,
        'message'         => "Some message",

        'payload'         => {},
        'last_updated_at' => 1344855831
    }
  end

  specify ".status_key" do
    jid = SecureRandom.base64
    described_class.status_key(jid).should == "sidekiq_status:#{jid}"
  end

  specify ".kill_key" do
    described_class.kill_key.should == described_class::KILL_KEY
  end


  context "finders" do
    let!(:containers) do
      described_class::STATUS_NAMES.inject({}) do |accum, status_name|
        container = described_class.create()
        container.update_attributes(:status => status_name)

        accum[status_name] = container
        accum
      end
    end

    specify ".size" do
      described_class.size.should == containers.size
    end

    specify ".status_jids" do
      expected = containers.values.map(&:jid).map{ |jid| [jid, anything()] }
      described_class.status_jids.should =~ expected
      described_class.status_jids(0, 0).size.should == 1
    end

    specify ".statuses" do
      described_class.statuses.should be_all{|st| st.is_a?(described_class) }
      described_class.statuses.size.should == containers.size
      described_class.statuses(0, 0).size.should == 1
    end

    describe ".delete" do
      before do
        described_class.status_jids.map(&:first).should =~ containers.values.map(&:jid)
      end

      specify "deletes jobs in specific status" do
        statuses_to_delete = ['waiting', 'complete']
        described_class.delete(statuses_to_delete)

        described_class.status_jids.map(&:first).should =~ containers.
            reject{ |status_name, container|  statuses_to_delete.include?(status_name) }.
            values.
            map(&:jid)
      end

      specify "deletes jobs in all statuses" do
        described_class.delete()

        described_class.status_jids.should be_empty
      end
    end
  end

  specify ".create" do
    expect(SecureRandom).to receive(:hex).with(12).and_return(jid)
    args = ['arg1', 'arg2', {arg3: 'val3'}]

    container = described_class.create('args' => args)
    container.should be_a(described_class)
    container.args.should == args

    # Check default values are set
    test_container(container, described_class::DEFAULTS.reject{|k, v| k == 'args' }, jid)

    Sidekiq.redis do |conn|
      conn.exists(status_key).should be true
    end
  end

  describe ".load" do
    it "raises StatusNotFound exception if status is missing in Redis" do
      expect { described_class.load(jid) }.to raise_exception(described_class::StatusNotFound, jid)
    end

    it "loads a container from the redis key" do
      json = Sidekiq.dump_json(sample_json_hash)
      Sidekiq.redis { |conn| conn.set(status_key, json) }

      container = described_class.load(jid)
      test_container(container, sample_json_hash, jid)
    end

    it "cleans up unprocessed expired kill requests as well" do
      Sidekiq.redis do |conn|
        conn.zadd(described_class.kill_key, [
            [(Time.now - described_class.ttl - 1).to_i, 'a'],
            [(Time.now - described_class.ttl + 1).to_i, 'b'],
        ]
        )
      end

      json = Sidekiq.dump_json(sample_json_hash)
      Sidekiq.redis { |conn| conn.set(status_key, json) }
      described_class.load(jid)

      Sidekiq.redis do |conn|
        conn.zscore(described_class.kill_key, 'a').should be_nil
        conn.zscore(described_class.kill_key, 'b').should_not be_nil
      end
    end
  end

  specify "#dump" do
    hash = sample_json_hash.reject{ |k, v| k == 'last_updated_at' }
    container = described_class.new(jid, hash)
    dump = container.send(:dump)
    dump.should == hash.merge('last_updated_at' => Time.now.to_i)
  end

  specify "#save saves container to Redis" do
    hash = sample_json_hash.reject{ |k, v| k == 'last_updated_at' }
    described_class.new(jid, hash).save

    result = Sidekiq.redis{ |conn| conn.get(status_key) }
    result = Sidekiq.load_json(result)

    result.should == hash.merge('last_updated_at' => Time.now.to_i)

    Sidekiq.redis{ |conn| conn.ttl(status_key).should >= 0 }
  end

  specify "#delete" do
    Sidekiq.redis do |conn|
      conn.set(status_key, "something")
      conn.zadd(described_class.kill_key, 0, jid)
    end

    container = described_class.new(jid)
    container.delete

    Sidekiq.redis do |conn|
      conn.exists(status_key).should be false
      conn.zscore(described_class.kill_key, jid).should be_nil
    end
  end

  specify "#request_kill, #should_kill?, #killable?" do
    container = described_class.new(jid)
    container.kill_requested?.should be_falsey
    container.should be_killable

    Sidekiq.redis do |conn|
      conn.zscore(described_class.kill_key, jid).should be_nil
    end


    container.request_kill

    Sidekiq.redis do |conn|
      conn.zscore(described_class.kill_key, jid).should == Time.now.to_i
    end
    container.should be_kill_requested
    container.should_not be_killable
  end

  specify "#kill" do
    container = described_class.new(jid)
    container.request_kill
    Sidekiq.redis do |conn|
      conn.zscore(described_class.kill_key, jid).should == Time.now.to_i
    end
    container.status.should_not == 'killed'


    container.kill

    Sidekiq.redis do |conn|
      conn.zscore(described_class.kill_key, jid).should be_nil
    end

    container.status.should == 'killed'
    described_class.load(jid).status.should == 'killed'
  end

  specify "#pct_complete" do
    container = described_class.new(jid)
    container.at = 1
    container.total = 100
    container.pct_complete.should == 1

    container.at = 5
    container.total = 200
    container.pct_complete.should == 3 # 2.5.round(0) => 3
  end

  context "setters" do
    let(:container) { described_class.new(jid) }

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
      reloaded_container = described_class.load(container.jid)

      reloaded_container.at.should == 1
      reloaded_container.total.should == 3
      reloaded_container.message.should == 'msg'
      reloaded_container.status.should == 'working'

      expect{ container.update_attributes(:at => 'Invalid') }.to raise_exception(ArgumentError)
    end
  end

  context "predicates" do
    described_class::STATUS_NAMES.each do |status_name1|
      context "status is #{status_name1}" do
        subject{ described_class.create().tap{|c| c.status = status_name1} }

        its("#{status_name1}?") { should be true }

        (described_class::STATUS_NAMES - [status_name1]).each do |status_name2|
          its("#{status_name2}?") { should be false }
        end
      end
    end
  end
end