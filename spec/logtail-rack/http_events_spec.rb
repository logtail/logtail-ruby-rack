require "spec_helper"
require "logtail-rack/config"
require 'stringio'


RSpec.describe Logtail::Integrations::Rack::HTTPEvents do
  let(:app) { ->(env) { [200, env, "app"] } }
  let(:mock_request) { Rack::MockRequest.env_for('https://example.com/test-page', { 'HTTP_AUTHORIZATION' => 'Bearer secret_token', 'HTTP_CONTENT_TYPE' => 'text/plain' }) }

  let :middleware do
    described_class.new(app)
  end

  it "log HTTP request and response" do
    logs = capture_logs { middleware.call mock_request }

    expect(logs.map { |log| log['message'] }).to match(['Started GET "/test-page"', /Completed 200 OK in \d+\.\d+ms/])
  end

  it "log the request and the response with this middleware's call as their runtime context" do
    logs = capture_logs { middleware.call mock_request }

    runtimes = logs.map { |log| log["context"]["runtime"] }
    expect(runtimes.map { |runtime| runtime["file"] }).to all(end_with("lib/logtail-rack/http_events.rb"))
    expect(runtimes.map { |runtime| runtime["frame_label"] }).to all(match(/(\A|#)call\z/))
  end

  it "log the single event with this middleware's call as its runtime context" do
    stack = Logtail::Integrations::Rack::HTTPContext.new(middleware)
    logs = capture_logs { with_collapse_into_single_event { stack.call mock_request } }

    runtime = logs.first["context"]["runtime"]
    expect(runtime["file"]).to end_with("lib/logtail-rack/http_events.rb")
    expect(runtime["frame_label"]).to match(/(\A|#)call\z/)
  end

  it "return the app's response when collapsing into a single event without HTTPContext" do
    app = ->(env) { [200, { "content-type" => "text/plain" }, ["hello"]] }

    response = nil
    logs = capture_logs { with_collapse_into_single_event { response = described_class.new(app).call(mock_request) } }

    expect(response).to eq([200, { "content-type" => "text/plain" }, ["hello"]])
    expect(logs.map { |log| log['message'] }).to match([/\ACompleted 200 OK in \d+\.\d+ms\z/])
  end

  it "capture the request body and leave it for the app" do
    app = ->(env) { [200, { "content-type" => "text/plain" }, [env["rack.input"].read]] }
    request = Rack::MockRequest.env_for('https://example.com/form', method: "POST", input: "name=value")

    response = nil
    logs = capture_logs { with_capture_request_body { response = described_class.new(app).call(request) } }

    expect(response[2]).to eq(["name=value"])
    expect(logs.first["event"]["http_request_received"]["body"]).to eq("name=value")
  end

  it "leave the request body for the app when the input can't be rewound" do
    app = ->(env) { [200, { "content-type" => "text/plain" }, [env["rack.input"].read]] }
    # Rack 3 doesn't require rack.input to be rewindable
    input = StringIO.new("name=value")
    input.singleton_class.send(:undef_method, :rewind)
    request = Rack::MockRequest.env_for('https://example.com/form', method: "POST", input: input)

    response = nil
    logs = capture_logs { with_capture_request_body { response = described_class.new(app).call(request) } }

    expect(response).to eq([200, { "content-type" => "text/plain" }, ["name=value"]])
    expect(logs.first["event"]["http_request_received"]["body"]).to be_nil
  end

  it "return the app's response when capturing the request body without a request input" do
    app = ->(env) { [200, { "content-type" => "text/plain" }, ["hello"]] }
    # Rack 3.1 and later may leave rack.input out
    request = Rack::MockRequest.env_for('https://example.com/test-page')
    request.delete("rack.input")

    response = nil
    logs = capture_logs { with_capture_request_body { response = described_class.new(app).call(request) } }

    expect(response).to eq([200, { "content-type" => "text/plain" }, ["hello"]])
    expect(logs.first["event"]["http_request_received"]["body"]).to be_nil
  end

  it "log a captured Array response body as one String" do
    app = ->(env) { [200, { "content-type" => "text/plain" }, ["hello", " world"]] }

    logs = capture_logs { with_capture_response_body { described_class.new(app).call(mock_request) } }

    expect(logs.last["event"]["http_response_sent"]["body"]).to eq("hello world")
  end

  it "skip capturing a response body that isn't an Array and return it untouched" do
    # Can be iterated only once, by the server
    body = Object.new
    def body.each
      yield "hello"
    end
    app = ->(env) { [200, { "content-type" => "text/plain" }, body] }

    response = nil
    logs = capture_logs { with_capture_response_body { response = described_class.new(app).call(mock_request) } }

    expect(response[2]).to be(body)
    expect(logs.last["event"]["http_response_sent"]["body"]).to be_nil
  end

  it "return the app's response and log the response when logging the request raises" do
    app = ->(env) { [200, { "content-type" => "text/plain" }, ["hello"]] }
    # Rack::Request#host raises ArgumentError for invalid UTF-8 in a UTF-8 string
    request = Rack::MockRequest.env_for('https://example.com/test-page', 'HTTP_X_FORWARDED_HOST' => "\xFF")

    response = nil
    logs = nil
    debug_logs = capture_debug_logs { logs = capture_logs { response = described_class.new(app).call(request) } }

    expect(response).to eq([200, { "content-type" => "text/plain" }, ["hello"]])
    expect(logs.map { |log| log['message'] }).to match([/\ACompleted 200 OK in \d+\.\d+ms\z/])
    expect(debug_logs).to include("Logtail::Integrations::Rack::HTTPEvents could not log an event: #<ArgumentError: invalid byte sequence in UTF-8>")
  end

  it "return the app's response when the logger raises" do
    app = ->(env) { [200, { "content-type" => "text/plain" }, ["hello"]] }
    logger = Logtail::Logger.new(StringIO.new)
    # Like the JSON formatter does with json 3 and ActiveSupport 8.0 or older
    logger.formatter = ->(*) { raise ArgumentError, "unknown keyword: :quirks_mode" }
    allow(Logtail::Config.instance).to receive(:logger).and_return(logger)

    response = nil
    debug_logs = capture_debug_logs { response = described_class.new(app).call(mock_request) }

    expect(response).to eq([200, { "content-type" => "text/plain" }, ["hello"]])
    expect(debug_logs.scan("Logtail::Integrations::Rack::HTTPEvents could not log an event: #<ArgumentError: unknown keyword: :quirks_mode>").length).to eq(2)
  end

  it "log HTTP request headers, filtering the Authorization header by default" do
    logs = capture_logs { middleware.call mock_request }

    request_headers_json = logs.first["event"]["http_request_received"]["headers_json"]
    expect(JSON.parse(request_headers_json)).to eq({"Authorization" => "[FILTERED]", "Content_Type" => "text/plain"})
  end

  it "filter credential headers in the request and the response by default" do
    app = ->(env) { [200, { "Content-Type" => "text/plain", "Set-Cookie" => "session=abc" }, "app"] }
    request = Rack::MockRequest.env_for('https://example.com/test-page', {
      'HTTP_AUTHORIZATION' => 'Bearer secret_token',
      'HTTP_PROXY_AUTHORIZATION' => 'Basic cHJveHk6c2VjcmV0',
      'HTTP_COOKIE' => 'session=abc',
      'HTTP_CONTENT_TYPE' => 'text/plain',
    })

    logs = capture_logs { described_class.new(app).call request }

    request_headers_json = logs.first["event"]["http_request_received"]["headers_json"]
    expect(JSON.parse(request_headers_json)).to eq({"Authorization" => "[FILTERED]", "Proxy_Authorization" => "[FILTERED]", "Cookie" => "[FILTERED]", "Content_Type" => "text/plain"})
    response_headers_json = logs.last["event"]["http_response_sent"]["headers_json"]
    expect(JSON.parse(response_headers_json)).to eq({"Content-Type" => "text/plain", "Set-Cookie" => "[FILTERED]"})
  end

  it "log every header when http_header_filters is set to an empty list" do
    logs = capture_logs { with_http_header_filters([]) { middleware.call mock_request } }

    request_headers_json = logs.first["event"]["http_request_received"]["headers_json"]
    expect(JSON.parse(request_headers_json)).to eq({"Authorization" => "Bearer secret_token", "Content_Type" => "text/plain"})
  end

  it "filter HTTP request headers using http_header_filters" do
    logs = capture_logs { with_http_header_filters(%w[Authorization]) { middleware.call mock_request } }

    request_headers_json = logs.first["event"]["http_request_received"]["headers_json"]
    expect(JSON.parse(request_headers_json)).to eq({"Authorization" => "[FILTERED]", "Content_Type" => "text/plain"})
  end

  it "filter HTTP request headers using http_header_filters without regard to case or dashes" do
    logs = capture_logs { with_http_header_filters(%w[authorization CONTENT-TYPE]) { middleware.call mock_request } }

    request_headers_json = logs.first["event"]["http_request_received"]["headers_json"]
    expect(JSON.parse(request_headers_json)).to eq({"Authorization" => "[FILTERED]", "Content_Type" => "[FILTERED]"})
  end

  it "ignores non-existent headers in http_header_filters" do
    logs = capture_logs { with_http_header_filters(%w[Not_Found_Header]) { middleware.call mock_request } }

    request_headers_json = logs.first["event"]["http_request_received"]["headers_json"]
    expect(JSON.parse(request_headers_json)).to eq({"Authorization" => "Bearer secret_token", "Content_Type" => "text/plain"})
  end

  it "log the content length of a Rack 3 response with lower-case header names" do
    app = ->(env) { [200, { "content-type" => "text/plain", "content-length" => "5" }, ["hello"]] }

    logs = capture_logs { described_class.new(app).call mock_request }

    http_response_sent = logs.last["event"]["http_response_sent"]
    expect(http_response_sent["content_length"]).to eq(5)
    expect(JSON.parse(http_response_sent["headers_json"])).to eq({"content-type" => "text/plain", "content-length" => "5"})
  end

  it "log the content length of a response with a Content-Length header" do
    app = ->(env) { [200, { "Content-Type" => "text/plain", "Content-Length" => "5" }, ["hello"]] }

    logs = capture_logs { described_class.new(app).call mock_request }

    http_response_sent = logs.last["event"]["http_response_sent"]
    expect(http_response_sent["content_length"]).to eq(5)
    expect(JSON.parse(http_response_sent["headers_json"])).to eq({"Content-Type" => "text/plain", "Content-Length" => "5"})
  end

  it "log the content length of a response with Rack::Headers" do
    skip "Rack::Headers is new in Rack 3" unless defined?(Rack::Headers)
    app = ->(env) { [200, Rack::Headers["Content-Type" => "text/plain", "Content-Length" => "5"], ["hello"]] }

    logs = capture_logs { described_class.new(app).call mock_request }

    http_response_sent = logs.last["event"]["http_response_sent"]
    expect(http_response_sent["content_length"]).to eq(5)
    expect(JSON.parse(http_response_sent["headers_json"])).to eq({"content-type" => "text/plain", "content-length" => "5"})
  end

  it "log the content length of a Rack 3 response in the single collapsed event" do
    app = ->(env) { [200, { "content-type" => "text/plain", "content-length" => "5" }, ["hello"]] }
    stack = Logtail::Integrations::Rack::HTTPContext.new(described_class.new(app))

    logs = capture_logs { with_collapse_into_single_event { stack.call mock_request } }

    expect(logs.length).to eq(1)
    expect(logs.first["event"]["http_response_sent"]["content_length"]).to eq(5)
  end

  it "log the response duration from the monotonic clock in milliseconds, rounded to one decimal" do
    app = ->(env) { [200, { "content-type" => "text/plain" }, ["hello"]] }
    allow(Process).to receive(:clock_gettime).and_call_original
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(100.0, 100.0392345)

    logs = capture_logs { described_class.new(app).call mock_request }

    expect(logs.last["message"]).to eq("Completed 200 OK in 39.2ms")
    expect(logs.last["event"]["http_response_sent"]["duration_ms"]).to eq(39.2)
  end

  it "log the response duration rounded to one decimal in the single collapsed event" do
    app = ->(env) { [200, { "content-type" => "text/plain" }, ["hello"]] }
    stack = Logtail::Integrations::Rack::HTTPContext.new(described_class.new(app))
    allow(Process).to receive(:clock_gettime).and_call_original
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(100.0, 100.0392345)

    logs = capture_logs { with_collapse_into_single_event { stack.call mock_request } }

    expect(logs.first["message"]).to eq("GET /test-page completed with 200 OK in 39.2ms")
    expect(logs.first["event"]["http_response_sent"]["duration_ms"]).to eq(39.2)
  end

  def capture_logs(&blk)
    old_logger = Logtail::Config.instance.logger

    string_io = StringIO.new
    logger = Logtail::Logger.new(string_io)
    logger.formatter = Logtail::Logger::JSONFormatter.new
    Logtail::Config.instance.logger = logger

    blk.call

    string_io.string.split("\n").map { |record| JSON.parse(record) }
  ensure
    Logtail::Config.instance.logger = old_logger
  end

  def capture_debug_logs(&blk)
    string_io = StringIO.new
    Logtail::Config.instance.debug_logger = ::Logger.new(string_io)

    blk.call

    string_io.string
  ensure
    Logtail::Config.instance.debug_logger = nil
  end

  def with_capture_request_body(&blk)
    Logtail::Integrations::Rack::HTTPEvents.capture_request_body = true

    blk.call
  ensure
    Logtail::Integrations::Rack::HTTPEvents.capture_request_body = false
  end

  def with_capture_response_body(&blk)
    Logtail::Integrations::Rack::HTTPEvents.capture_response_body = true

    blk.call
  ensure
    Logtail::Integrations::Rack::HTTPEvents.capture_response_body = false
  end

  def with_http_header_filters(headers, &blk)
    Logtail::Integrations::Rack::HTTPEvents.http_header_filters = headers

    blk.call
  ensure
    Logtail::Integrations::Rack::HTTPEvents.http_header_filters = Logtail::Integrations::Rack::HTTPEvents::DEFAULT_HTTP_HEADER_FILTERS
  end

  def with_collapse_into_single_event(&blk)
    Logtail::Integrations::Rack::HTTPEvents.collapse_into_single_event = true

    blk.call
  ensure
    Logtail::Integrations::Rack::HTTPEvents.collapse_into_single_event = false
  end
end
