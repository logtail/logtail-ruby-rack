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
            host: request.host,
            method: request.request_method,
            path: request.path,
            remote_addr: request.ip,
            request_id: request.request_id
          )

          CurrentContext.add(context.to_hash)
          @app.call(env)
        end
      end
    end
  end
end
