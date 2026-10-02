require "logtail/config"

module Logtail
  module Integrations
    module Rack
      # Base class that all Logtail Rack middlewares extend. See the class level methods for
      # configuration options.
      class Middleware
        class << self
          # Easily enable / disable specific middlewares.
          #
          # @example
          #   Logtail::Integrations::Rack::UserContext.enabled = false
          def enabled=(value)
            @enabled = value
          end

          # Accessor method for {#enabled=}.
          def enabled?
            @enabled != false
          end
        end

        def initialize(app)
          @app = app
        end

        private
          # Logging must never fail the request, so an error raised while building or writing an event
          # only goes to the debug logger. The middlewares call the logger themselves, so that the
          # runtime context of the line points to them, and rescue the error with this method:
          #
          #   Config.instance.logger.info do
          #     ...
          #   end rescue logging_failed($!)
          def logging_failed(error)
            Config.instance.debug { "#{self.class.name} could not log an event: #{error.inspect}\n\n#{error.backtrace}" }
          end
      end
    end
  end
end
