# -*- encoding : utf-8 -*-
require 'spec_helper'

describe SidekiqStatus::ClientMiddleware do
  describe "cryo28/sidekiq_status#11 regression" do
    describe "#call" do
      before do
        SidekiqStatus::Container.should_receive(:create).with(hash_including('worker' => 'TestWorker1'))
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
    SidekiqStatus::Container.should_not_receive(:create)

    subject.call("TestWorker1", { "at" => Time.now }, nil) do
    end
  end
end
