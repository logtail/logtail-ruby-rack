# Example project

To help you get started with using Better Stack in your Rack projects, we have prepared a simple program that showcases the usage of Logtail logger.

## Download and install the example project

You can download the [example project](https://github.com/logtail/logtail-ruby-rack/tree/main/example-project) from GitHub directly or you can clone it to a select directory. Make sure you are in the projects directory and run the following command:

```bash
bundle install
```

This will install all dependencies listed in the `Gemfile`.

## Run the example project

To run the example application, set your source token and ingesting host, which you can find by going to [Better Stack Telemetry](https://telemetry.betterstack.com/dashboard) -> Source -> Configure, and start the server:

```bash
BETTER_STACK_SOURCE_TOKEN=<source_token> BETTER_STACK_INGESTING_HOST=<ingesting_host> bundle exec rackup
```

This will start a local server, and you can visit [http://localhost:9292](http://localhost:9292) in your browser.

You should see the following output:

```bash
All done!
Log into your Better Stack account to check your logs.
```

This will create a total of 5 different logs: the request, an info, a debug and a warning line from the app, and the response. You can review these logs in Better Stack.

You can visit any path on the server to see the request path being logged in context. Visit [/error](http://localhost:9292/error) to see an example exception being logged.

Stop the server with Ctrl+C. The logs still buffered are sent before it exits.
