require "set"

require "logtail/config"
require "logtail/contexts/http"
require "logtail/current_context"
require "logtail-rack/http_request"
require "logtail-rack/http_response"
require "logtail-rack/middleware"

module Logtail
  module Integrations
    module Rack
      # A Rack middleware that is reponsible for capturing and logging HTTP server requests and
      # response events. The {Events::HTTPRequest} and {Events::HTTPResponse} events
      # respectively.
      class HTTPEvents < Middleware
        class << self
          # Allows you to capture the HTTP request body, default is off (false).
          #
          # Capturing HTTP bodies can be extremely helpful when debugging issues,
          # but please proceed with caution:
          #
          # 1. Capturing HTTP bodies can use quite a bit of data (this can be mitigated, see below)
          #
          # If you opt to capture bodies, you can also truncate the size to reduce the data
          # captured. See {Events::HTTPRequest}.
          #
          # @example
          #   Logtail::Integrations::Rack::HTTPEvents.capture_request_body = true
          def capture_request_body=(value)
            @capture_request_body = value
          end

          # Accessor method for {#capture_request_body=}
          def capture_request_body?
            @capture_request_body == true
          end

          # Just like {#capture_request_body=} but for the {Events::HTTPResponse} event.
          # Please see {#capture_request_body=} for more details. The documentation there also
          # applies here.
          def capture_response_body=(value)
            @capture_response_body = value
          end

          # Accessor method for {#capture_response_body=}
          def capture_response_body?
            @capture_response_body == true
          end

          # Collapse both the HTTP request and response events into a single log line event.
          # While we don't recommend this, it can help to reduce log volume if desired.
          # The reason we don't recommend this, is because the logging service you use should
          # not be so expensive that you need to strip out useful logs. It should also provide
          # the tools necessary to properly search your logs and reduce noise. Such as viewing
          # logs for a specific request.
          #
          # To provide an example. This setting turns this:
          #
          #   Started GET "/" for 127.0.0.1 at 2012-03-10 14:28:14 +0100
          #   Completed 200 OK in 79ms (Views: 78.8ms | ActiveRecord: 0.0ms)
          #
          # Into this:
          #
          #   Get "/" sent 200 OK in 79ms
          #
          # The single event is still a {Logtail::Events::HTTPResponse} event. Because
          # we capture HTTP context, you still get the HTTP details, but you will not get
          # all of the request details that the {Logtail::Events::HTTPRequest} event would
          # provide.
          #
          # @example
          #   Logtail::Integrations::Rack::HTTPEvents.collapse_into_single_event = true
          def collapse_into_single_event=(value)
            @collapse_into_single_event = value
          end

          # Accessor method for {#collapse_into_single_event=}.
          def collapse_into_single_event?
            @collapse_into_single_event == true
          end

          # This setting allows you to silence requests based on any conditions you desire.
          # We require a block because it gives you complete control over how you want to
          # silence requests. The first parameter being the traditional Rack env hash, the
          # second being a [Rack Request](http://www.rubydoc.info/gems/rack/Rack/Request) object.
          #
          # @example
          #   Integrations::Rack::HTTPEvents.silence_request = lambda do |rack_env, rack_request|
          #     rack_request.path == "/_health"
          #   end
          def silence_request=(proc)
            if proc && !proc.is_a?(Proc)
              raise ArgumentError.new("The value passed to #silence_request must be a Proc")
            end

            @silence_request = proc
          end

          # Accessor method for {#silence_request=}
          def silence_request
            @silence_request
          end

          # Filter sensitive HTTP headers (such as "Authorization: Bearer secret_token")
          #
          # Filtered HTTP header values will be sent to Better Stack as "[FILTERED]"
          #
          # @example
          #   Logtail::Integrations::Rack::HTTPEvents.http_header_filters = ["Authorization"]
          def http_header_filters=(value)
            @http_header_filters = value.map { |header_name| normalize_header_name(header_name) }
          end

          # Accessor method for {#http_header_filters=}
          def http_header_filters
            @http_header_filters
          end

          def normalize_header_name(name)
            name.to_s.downcase.gsub("-", "_")
          end
        end

        CONTENT_LENGTH_KEY = 'Content-Length'.freeze

        def call(env)
          request = Util::Request.new(env)

          if silenced?(env, request)
            if Config.instance.logger.respond_to?(:silence)
              Config.instance.logger.silence do
                @app.call(env)
              end
            else
              @app.call(env)
            end

          elsif collapse_into_single_event?
            request_start = Time.now
            status, headers, body = @app.call(env)
            request_end = Time.now

            Config.instance.logger.info do
              http_context = CurrentContext.fetch(:http)
              content_length = safe_to_i(headers[CONTENT_LENGTH_KEY])
              duration_ms = (request_end - request_start) * 1000.0

              http_response = HTTPResponse.new(
                content_length: content_length,
                headers: filter_http_headers(headers),
                http_context: http_context,
                request_id: request.request_id,
                status: status,
                duration_ms: duration_ms,
              )

              {
                message: http_response.message,
                event: {
                  http_response_sent: {
                    body: http_response.body,
                    content_length: http_response.content_length,
                    headers_json: http_response.headers_json,
                    request_id: http_response.request_id,
                    service_name: http_response.service_name,
                    status: http_response.status,
                    duration_ms: http_response.duration_ms,
                  }
                }
              }
            end

            [status, headers, body]
          else
            Config.instance.logger.info do
              event_body = capture_request_body? ? request.body_content : nil
              http_request = HTTPRequest.new(
                body: event_body,
                content_length: safe_to_i(request.content_length),
                headers: filter_http_headers(request.headers),
                host: force_encoding(request.host),
                method: request.request_method,
                path: request.path,
                port: request.port,
                query_string: force_encoding(request.query_string),
                request_id: request.request_id,
                scheme: force_encoding(request.scheme),
              )

              {
                message: http_request.message,
                event: {
                  http_request_received: {
                    body: http_request.body,
                    content_length: http_request.content_length,
                    headers_json: http_request.headers_json,
                    host: http_request.host,
                    method: http_request.method,
                    path: http_request.path,
                    port: http_request.port,
                    query_string: http_request.query_string,
                    request_id: http_request.request_id,
                    scheme: http_request.scheme,
                    service_name: http_request.service_name,
                  }
                }
              }
            end

            request_start = Time.now
            status, headers, body = @app.call(env)
            request_end = Time.now

            Config.instance.logger.info do
              event_body = capture_response_body? ? body : nil
              content_length = safe_to_i(headers[CONTENT_LENGTH_KEY])
              duration_ms = (request_end - request_start) * 1000.0

              http_response = HTTPResponse.new(
                body: event_body,
                content_length: content_length,
                headers: filter_http_headers(headers),
                request_id: request.request_id,
                status: status,
                duration_ms: duration_ms,
              )

              {
                message: http_response.message,
                event: {
                  http_response_sent: {
                    body: http_response.body,
                    content_length: http_response.content_length,
                    headers_json: http_response.headers_json,
                    request_id: http_response.request_id,
                    service_name: http_response.service_name,
                    status: http_response.status,
                    duration_ms: http_response.duration_ms,
                  }
                }
              }
            end

            [status, headers, body]
          end
        end

        private
          def capture_request_body?
            self.class.capture_request_body?
          end

          def capture_response_body?
            self.class.capture_response_body?
          end

          def collapse_into_single_event?
            self.class.collapse_into_single_event?
          end

          def silenced?(env, request)
            if !self.class.silence_request.nil?
              self.class.silence_request.call(env, request)
            else
              false
            end
          end

          def filter_http_headers(headers)
            headers.each do |name, _|
              normalized_header_name = self.class.normalize_header_name(name)
              headers[name] = "[FILTERED]" if self.class.http_header_filters&.include?(normalized_header_name)
            end
          end

          def safe_to_i(val)
            val.nil? ? nil : val.to_i
          end

          def force_encoding(value)
            if value.respond_to?(:force_encoding)
              value.dup.force_encoding('UTF-8')
            else
              value
            end
          end
      end
    end
  end
end
