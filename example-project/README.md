# Example project

To help you get started with using Better Stack in your Rack projects, we have prepared a simple program that showcases the usage of Logtail logger.

## Download and install the example project

You can download the [example project](https://github.com/logtail/logtail-ruby-rack/tree/main/example-project) from GitHub directly or you can clone it to a select directory. Make sure you are in the projects directory and run the following command:

```bash
bundle install
```

This will install all dependencies listed in the `Gemfile.lock` file.

Then replace `<source_token>` and `<ingesting_host>` in `config.ru` with your actual source token and ingesting host which you can find by going to [Better Stack Telemetry](https://teleemetry.betterstack.com/dashboard) -> Source -> Configure.

```ruby
http_io_device = Logtail::LogDevices::HTTP.new("<source_token>", logtail_host: "<ingesting_host>")
```

## Run the example project

To run the example application, run the following command:

```bash
rackup
```

This will start a local server and you visit [http://127.0.0.1:9292](http://127.0.0.1:9292) in your browser.

You should see the following output:

```bash
All done!
Log into your Logtail account to check your logs.
```

This will create a total of 4 different logs. You can review these logs in Better Stack.

You can visit any path on the server to see the request path being logged in context. Visit [/error](http://127.0.0.1:9292) to see an example exception being logged.
