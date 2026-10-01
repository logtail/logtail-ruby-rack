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
          # Logs the event the block builds. Logging must never fail the request, so an error raised
          # while building or writing the event only goes to the debug logger.
          def log_safely(severity, &block)
            Config.instance.logger.public_send(severity, &block)
          rescue StandardError => e
            Config.instance.debug { "#{self.class.name} could not log an event: #{e.inspect}\n\n#{e.backtrace}" }
          end
      end
    end
  end
end
