require 'logtail-rack'
require './logging_app'

# Initialization of logging middlewares
use Logtail::Integrations::Rack::HTTPContext
use Logtail::Integrations::Rack::HTTPEvents
use Logtail::Integrations::Rack::ErrorEvent

# HTTP IO device sends logs to Better Stack, to the source whose token and ingesting host are in
# the BETTER_STACK_SOURCE_TOKEN and BETTER_STACK_INGESTING_HOST environment variables
source_token = ENV["BETTER_STACK_SOURCE_TOKEN"].to_s
ingesting_host = ENV["BETTER_STACK_INGESTING_HOST"].to_s
if source_token.empty? || ingesting_host.empty?
  abort "Usage: BETTER_STACK_SOURCE_TOKEN=<source_token> BETTER_STACK_INGESTING_HOST=<ingesting_host> bundle exec rackup"
end
http_io_device = Logtail::LogDevices::HTTP.new(source_token, ingesting_host: ingesting_host)

# Sends the logs still buffered when the server stops
at_exit { http_io_device.close }

# STDOUT IO device sends logs to console output
stdout_io_device = STDOUT

# Logger initialization, you can use any number of IO devices
logger = Logtail::Logger.new(http_io_device, stdout_io_device)
Logtail::Config.instance.logger = logger

# App initialization
run LoggingApp.new(logger)
