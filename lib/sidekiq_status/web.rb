module SidekiqStatus
  # Hook into *Sidekiq::Web* Sinatra app which adds a new "/statuses" page
  module Web
    # Location of SidekiqStatus::Web view templates
    VIEW_PATH = File.expand_path('../../../web/views', __FILE__)

    # @param [Sidekiq::Web] app
    def self.registered(app)
      app.helpers do
        def sidekiq_status_template(name)
          path = File.join(VIEW_PATH, name.to_s) + ".erb"
          File.open(path).read
        end

        def redirect_to(subpath)
          if respond_to?(:to)
            # Sinatra-based web UI
            redirect to(subpath)
          else
            # Non-Sinatra based web UI (Sidekiq 4.2+)
            "#{root_path}#{subpath}"
          end
        end
      end

      app.get '/statuses' do
        @count = (params[:count] || 25).to_i

        @current_page = (params[:page] || 1).to_i
        @current_page = 1 unless @current_page > 0

        @total_size = SidekiqStatus::Container.size

        pageidx = @current_page - 1
        @statuses = SidekiqStatus::Container.statuses(pageidx * @count, (pageidx + 1) * @count)

        erb(sidekiq_status_template(:statuses))
      end

      app.get '/statuses/:jid' do
        @status = SidekiqStatus::Container.load(params[:jid])
        erb(sidekiq_status_template(:status))
      end

      app.get '/statuses/:jid/kill' do
        SidekiqStatus::Container.load(params[:jid]).request_kill
        redirect_to :statuses
      end

      app.get '/statuses/delete/all' do
        SidekiqStatus::Container.delete
        redirect_to :statuses
      end

      app.get '/statuses/delete/complete' do
        SidekiqStatus::Container.delete('complete')
        redirect_to :statuses
      end

      app.get '/statuses/delete/finished' do
        SidekiqStatus::Container.delete(SidekiqStatus::Container::FINISHED_STATUS_NAMES)
        redirect_to :statuses
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
