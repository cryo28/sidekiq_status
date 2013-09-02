# -*- encoding : utf-8 -*-
require 'spec_helper'

describe SidekiqStatus::ClientMiddleware do

  describe "#call" do

    #regression for issue #11
    it "handles worker as a class" do
       lambda do
         subject.call(TestWorker1, {}, nil) do
         end
       end.should_not raise_error
    end

    #regression for issue #11
    it "hadles worker as a string" do
       lambda do
         subject.call("TestWorker1", {}, nil) do
         end
       end.should_not raise_error
    end
  end
end
