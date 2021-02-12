require "logtail"

Logtail::Config.instance.define_singleton_method(:logrageify!) do
  integrations.rack.http_events.collapse_into_single_event = true
end

module Logtail
  class Config
    module Integrations
      extend self
      # Convenience module for accessing the various `Logtail::Integrations::Rack::*` classes
      # through the {Logtail::Config} object. Logtail couples configuration with the class
      # responsibls for implementing it. This provides for a tighter design, but also
      # requires the user to understand and access the various classes. This module aims
      # to provide a simple ruby-like configuration interface for internal Logtail classes.
      #
      # For example:
      #
      #     config = Logtail::Config.instance
      #     config.integrations.rack.http_events.enabled = false
      def rack
        Rack
      end

      module Rack
        extend self

        # Convenience method for accessing the {Logtail::Integrations::Rack::ErrorEvent}
        # middleware class specific configuration. See {Logtail::Integrations::Rack::ExceptionEvent}
        # for a list of methods available.
        #
        # @example
        #   config = Logtail::Config.instance
        #   config.integrations.rack.error_event.enabled = false
        def error_event
          Logtail::Integrations::Rack::ErrorEvent
        end

        # Convenience method for accessing the {Logtail::Integrations::Rack::HTTPContext}
        # middleware class specific configuration. See {Logtail::Integrations::Rack::HTTPContext}
        # for a list of methods available.
        #
        # @example
        #   config = Logtail::Config.instance
        #   config.integrations.rack.http_context.enabled = false
        def http_context
          Logtail::Integrations::Rack::HTTPContext
        end

        # Convenience method for accessing the {Logtail::Integrations::Rack::HTTPEvents}
        # middleware class specific configuration. See {Logtail::Integrations::Rack::HTTPEvents}
        # for a list of methods available.
        #
        # @example
        #   config = Logtail::Config.instance
        #   config.integrations.rack.http_events.enabled = false
        def http_events
          Logtail::Integrations::Rack::HTTPEvents
        end

        # Convenience method for accessing the {Logtail::Integrations::Rack::SessionContext}
        # middleware class specific configuration. See {Logtail::Integrations::Rack::SessionContext}
        # for a list of methods available.
        #
        # @example
        #   config = Logtail::Config.instance
        #   config.integrations.rack.session_context.enabled = false
        def session_context
          Logtail::Integrations::Rack::SessionContext
        end

        # Convenience method for accessing the {Logtail::Integrations::Rack::UserContext}
        # middleware class specific configuration. See {Logtail::Integrations::Rack::UserContext}
        # for a list of methods available.
        #
        # @example
        #   config = Logtail::Config.instance
        #   config.integrations.rack.user_context.enabled = false
        def user_context
          Logtail::Integrations::Rack::UserContext
        end
      end
    end
  end
end
