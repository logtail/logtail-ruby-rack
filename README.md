# 🪵 Logtail Integration For Rack

[![ISC License](https://img.shields.io/badge/license-ISC-ff69b4.svg)](LICENSE.md)
[![Gem Version](https://badge.fury.io/rb/logtail-rack.svg)](https://badge.fury.io/rb/logtail-rack)
[![Build Status](https://github.com/logtail/logtail-ruby-rack/workflows/build/badge.svg)](https://github.com/logtail/logtail-ruby-rack/actions?query=workflow%3Abuild)

This library integrates the [`logtail` Ruby library](https://github.com/logtail/logtail-ruby) with the [rack](https://github.com/rack/rack) framework,
turning your Rack logs into rich structured events.

* **Sign-up: [https://logtail.com](https://logtail.com)**

Collect logs directly from your Ruby on Rails projects. To start logging Ruby projects explore the [Logtail Ruby library](https://github.com/logtail/logtail-ruby).

[Logtail](https://betterstack.com/logtail) is a hosted service that centralizes all of your logs into one place. Allowing for analysis, correlation and filtering with SQL. Actionable Grafana dashboards and collaboration come built-in. Logtail works with [any language or platform and any data source](https://betterstack.com/docs/logs/).

### Features
- Simple integration.
- Support for structured logging and events.
- Automatically captures useful context.
- Performant, light weight, with a thoughtful design.

### Supported language versions
- Ruby 2.3 or newer
- Rack 1.2 or newer

# Installation
Install the Logtail Rack client library, run the following command:

```bash
bundle add logtail-rack
```

Alternatively, add `gem "logtail-rack"` to your `Gemfile` manually and then run `bundle install`.

Then add following configuration into your `config.ru`:

```ruby
# Initialization of logging middlewares (you don't have to use all)
use Logtail::Integrations::Rack::HTTPContext
use Logtail::Integrations::Rack::HTTPEvents
use Logtail::Integrations::Rack::ErrorEvent
use Logtail::Integrations::Rack::UserContext
use Logtail::Integrations::Rack::SessionContext

http_io_device = Logtail::LogDevices::HTTP.new("<SOURCE_TOKEN>")
logger = Logtail::Logger.new(http_io_device)
Logtail::Config.instance.logger = logger

# Here is your application initialization
run ...
```

*Don't forget to replace `<SOURCE_TOKEN>` with your actual source token which you can find by going to [Better Stack Logs](https://logs.betterstack.com/dashboard) -> Source -> Edit.*

---

# Example project

To help you get started with using Better Stack in your Rails projects, we have prepared a simple program that showcases the usage of Logtail logger.

## Download and install the example project

You can download the [example project](https://github.com/logtail/logtail-ruby-rack/tree/main/example-project) from GitHub directly or you can clone it to a select directory. Make sure you are in the projects directory and run the following command:

```bash
bundle install
```

This will install all dependencies listed in the `Gemfile.lock` file.

Then replace `<SOURCE_TOKEN>` in `config.ru` with your actual source token which you can find by going to [Better Stack Logs](https://logs.betterstack.com/dashboard) -> Source -> Edit.

```ruby
http_io_device = Logtail::LogDevices::HTTP.new("<YOUR_ACTUAL_SOURCE_TOKEN>")
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

## Explore how example project works

Learn how to setup Ruby logging by exploring the workings of the [example project](https://github.com/logtail/logtail-ruby-rack/tree/main/example-project) in detail.
 
---

## Get in touch

Have any questions? Please explore the Better Stack [documentation](https://betterstack.com/docs/logs/) or contact our [support](https://betterstack.com/help).
