require 'logtail-rack'
require './logging_app'

# Initialization of logging middlewares
use Logtail::Integrations::Rack::HTTPContext
use Logtail::Integrations::Rack::HTTPEvents
use Logtail::Integrations::Rack::ErrorEvent

# HTTP IO device sends logs to Better Stack, replace <source_token> and <ingesting_host> with your real source token and ingesting host
http_io_device = Logtail::LogDevices::HTTP.new("<source_token>", ingesting_host: "<ingesting_host>")

# STDOUT IO device sends logs to console output
stdout_io_device = STDOUT

# Logger initialization, you can use any number of IO devices
logger = Logtail::Logger.new(http_io_device, stdout_io_device)
Logtail::Config.instance.logger = logger

# App initialization
logging_app = LoggingApp.new(logger)
run do |env|
  logging_app.run(env)
end
