module SidekiqStatus
  # Hook into *Sidekiq::Web* Sinatra app which adds a new "/statuses" page
  module Web
    # Location of SidekiqStatus::Web view templates
    VIEW_PATH = File.expand_path('../../../web/views', __FILE__)

    # @param [Sidekiq::Web] app
    def self.registered(app)
      app.helpers do
        # Calls the given block for every possible template file in views,
        # named name.ext, where ext is registered on engine.
        def find_template(views, name, engine, &block)
          super(VIEW_PATH, name, engine, &block)
          super
        end
      end

      app.get '/statuses' do
        @count = (params[:count] || 25).to_i

        @current_page = (params[:page] || 1).to_i
        @current_page = 1 unless @current_page > 0

        @total_size = SidekiqStatus::Container.size

        pageidx = @current_page - 1
        @statuses = SidekiqStatus::Container.statuses(pageidx * @count, (pageidx + 1) * @count)

        render(:slim, :statuses)
      end

      app.get '/statuses/:jid' do
        @status = SidekiqStatus::Container.load(params[:jid])
        render(:slim, :status)
      end

      app.get '/statuses/:jid/kill' do
        SidekiqStatus::Container.load(params[:jid]).request_kill
        redirect to(:statuses)
      end

      app.get '/statuses/delete/all' do
        SidekiqStatus::Container.delete
        redirect to(:statuses)
      end

      app.get '/statuses/delete/complete' do
        SidekiqStatus::Container.delete('complete')
        redirect to(:statuses)
      end

      app.get '/statuses/delete/finished' do
        SidekiqStatus::Container.delete(SidekiqStatus::Container::FINISHED_STATUS_NAMES)
        redirect to(:statuses)
      end
    end
  end
end

require 'sidekiq/web' unless defined?(Sidekiq::Web)
Sidekiq::Web.register(SidekiqStatus::Web)
if Sidekiq::Web.tabs.is_a?(Array)
  # For sidekiq < 2.5
  Sidekiq::Web.tabs << "statuses"
else
  Sidekiq::Web.tabs["Statuses"] = "statuses"
end
