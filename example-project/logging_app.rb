require 'logtail-rack'

class LoggingApp
  def initialize(logger)
    @logger = logger
  end

  def run(env)
    @logger.info("I am using Better Stack! 🚀")

    # You can also provide additional information when logging
    @logger.debug("Logging structured data...",
      name: {
        first: "John",
        last: "Smith"
      },
      id: 123456
    )

    raise RuntimeError.new("Visiting /error raises an error. You should see it in Better Stack.") if env["REQUEST_PATH"].start_with?("/error")

    [200, {}, ["All done!\nLog into your Logtail account to check your logs."]]
  end
end
