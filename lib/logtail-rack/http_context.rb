require "logtail/config"
require "logtail/contexts/http"
require "logtail/current_context"
require "logtail-rack/middleware"
require "logtail-rack/util/encoding"
require "logtail-rack/util/request"

module Logtail
  module Integrations
    module Rack
      # A Rack middleware that is reponsible for adding the HTTP context {Logtail::Contexts::HTTP}.
      class HTTPContext < Middleware
        def call(env)
          context = get_http_context(env)
          if context
            CurrentContext.with(context) do
              @app.call(env)
            end
          else
            @app.call(env)
          end
        end

        private
          def get_http_context(env)
            request = Util::Request.new(env)
            Contexts::HTTP.new(
              host: Util::Encoding.force_utf8_encoding(request.host),
              method: Util::Encoding.force_utf8_encoding(request.request_method),
              path: request.path,
              remote_addr: Util::Encoding.force_utf8_encoding(request.ip),
              request_id: request.request_id
            ).to_hash
          rescue StandardError => e
            Logtail::Config.instance.debug { "Could not build the HTTP context: #{e.inspect}\n\n#{e.backtrace}" }
            nil
          end
      end
    end
  end
end
