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
      end
    end
  end
end
