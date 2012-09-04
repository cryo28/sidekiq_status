# -*- encoding : utf-8 -*-
module SidekiqStatus
  module Worker
    def self.included(base)
      base.class_eval do
        include Sidekiq::Worker

        extend(ClassMethods)
        include(InstanceMethods)

        base.define_singleton_method(:new) do |*args, &block|
          super(*args, &block).extend(Prepending)
        end
      end
    end

    module Prepending
      def perform(jid)
        @status_container = SidekiqStatus::Container.load(jid)

        begin
          catch(:killed) do
            set_status('working')
            super(*@status_container.args)
            set_status('complete')
          end
        rescue Exception => exc
          set_status('failed', exc.class.name + ': ' + exc.message + "   \n\n " + exc.backtrace.join("\n    "))
          raise exc
        end
      end
    end

    module InstanceMethods
      def status_container
        kill if @status_container.kill_requested?
        @status_container
      end
      alias_method :sc, :status_container

      def kill
        # NOTE: status_container below should be accessed by instance var instead of an accessor method
        # because the second option will lead to infinite recursing
        @status_container.kill
        throw(:killed)
      end

      def set_status(status, message = nil)
        self.sc.update_attributes('status' => status, 'message' => message)
      end

      def at(at, message = nil)
        self.sc.update_attributes('at' => at, 'message' => message)
      end

      def total=(total)
        self.sc.update_attributes('total' => total)
      end

      def payload=(payload)
        self.sc.update_attributes('payload' => payload)
      end
    end

    module ClassMethods
      def perform_async(*args)
        status_container = SidekiqStatus::Container.create(*args)

        jid = super(*status_container.jid)

        return status_container.jid if jid

        status_container.delete
        jid
      end
    end
  end
end
