require "logtail/contexts/http"
require "logtail/current_context"
require "logtail-rack/middleware"
require "logtail-rack/util/request"

module Logtail
  module Integrations
    module Rack
      # A Rack middleware that is reponsible for adding the HTTP context {Logtail::Contexts::HTTP}.
      class HTTPContext < Middleware
        def call(env)
          request = Util::Request.new(env)
          context = Contexts::HTTP.new(
            host: request.host.force_encoding('UTF-8'),
            method: request.request_method.force_encoding('UTF-8'),
            path: request.path,
            remote_addr: request.ip.force_encoding('UTF-8'),
            request_id: request.request_id
          )

          CurrentContext.with(context.to_hash) do
            @app.call(env)
          end
        end
      end
    end
  end
end
