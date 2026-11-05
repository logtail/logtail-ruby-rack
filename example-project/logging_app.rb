require 'logtail-rack'

class LoggingApp
  def initialize(logger)
    @logger = logger
  end

  def call(env)
    raise RuntimeError.new("Visiting /error raises an error. You should see it in Better Stack.") if env["PATH_INFO"].start_with?("/error")

    @logger.info("I am using Better Stack! 🚀")

    # You can also provide additional information when logging
    @logger.debug("Logging structured data...",
      name: {
        first: "John",
        last: "Smith"
      },
      id: 123456
    )

    @logger.warn("Log structured data",
      item: {
        url: "https://fictional-store.com/item-123",
        price: 100.00
      }
    )

    [200, { "content-type" => "text/plain" }, ["All done!\nLog into your Better Stack account to check your logs.\n"]]
  end
end
