require "logtail/config"
require "logtail/contexts/session"
require "logtail-rack/middleware"

module Logtail
  module Integrations
    module Rack
      # A Rack middleware that is responsible for adding the Session context
      # {Logtail::Contexts::Session}.
      class SessionContext < Middleware
        def call(env)
          id = get_session_id(env)
          if id
            context = Contexts::Session.new(id: id)
            CurrentContext.with(context) do
              @app.call(env)
            end
          else
            @app.call(env)
          end
        end

        private
          def get_session_id(env)
            if session = env['rack.session']
              if session.respond_to?(:id)
                Logtail::Config.instance.debug { "Rack env session detected, using id attribute" }
                session.id
              elsif session.respond_to?(:[])
                Logtail::Config.instance.debug { "Rack env session detected, using the session_id key" }
                session["session_id"]
              else
                Logtail::Config.instance.debug { "Rack env session detected but could not extract id" }
                nil
              end
            else
              Logtail::Config.instance.debug { "No session data could be detected, skipping" }

              nil
            end
          rescue Exception => e
            nil
          end
      end
    end
  end
end
