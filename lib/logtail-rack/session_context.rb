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
                id = session.id
                # Since Rack 1.6.12 and 2.0.8 a Rack::Session::SessionId, which MessagePack can't encode. Its public id
                # is the session cookie of server-side stores, the private id a hash of it that can't be used as one.
                id.respond_to?(:private_id) ? id.private_id : id
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
