# -*- encoding : utf-8 -*-
require 'spec_helper'

describe SidekiqStatus::ClientMiddleware do
  describe "cryo28/sidekiq_status#11 regression" do
    describe "#call" do
      before do
        expect(SidekiqStatus::Container).to receive(:create).with(hash_including('worker' => 'TestWorker1'))
      end

      it "accepts a worker class" do
        subject.call(TestWorker1, {}, nil) do
        end
      end

      it "accepts a worker name string" do
        subject.call("TestWorker1", {}, nil) do
        end
      end
    end
  end

  it "does not create container for scheduled job" do
    expect(SidekiqStatus::Container).to_not receive(:create)

    subject.call("TestWorker1", { "at" => Time.now }, nil) do
    end
  end
end
