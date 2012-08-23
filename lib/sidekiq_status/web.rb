module SidekiqStatus
  module Web
    def self.extend_object(target)
      target.class_eval do
        # Calls the given block for every possible template file in views,
        # named name.ext, where ext is registered on engine.
        def find_template(views, name, engine, &block)
          super(File.expand_path('../../../web/views', __FILE__), name, engine, &block)
          super
        end

        get '/statuses' do
          @count = (params[:count] || 25).to_i

          @current_page = (params[:page] || 1).to_i
          @current_page = 1 unless @current_page > 0

          @total_size = SidekiqStatus::Container.size

          pageidx = @current_page - 1
          @statuses = SidekiqStatus::Container.statuses(pageidx * @count, (pageidx + 1) * @count)

          slim :statuses
        end

        get '/statuses/:uuid' do
          @status = SidekiqStatus::Container.load(params[:uuid])
          slim :status
        end

        get '/statuses/:uuid/kill' do
          SidekiqStatus::Container.load(params[:uuid]).request_kill
          redirect to(:statuses)
        end

        get '/statuses/delete/all' do
          SidekiqStatus::Container.delete
          redirect to(:statuses)
        end

        get '/statuses/delete/complete' do
          SidekiqStatus::Container.delete('complete')
          redirect to(:statuses)
        end

        get '/statuses/delete/finished' do
          SidekiqStatus::Container.delete(SidekiqStatus::Container::FINISHED_STATUS_NAMES)
          redirect to(:statuses)
        end
      end
    end
  end
end

require 'sidekiq/web'
Sidekiq::Web.extend(SidekiqStatus::Web)