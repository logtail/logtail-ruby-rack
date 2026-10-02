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
    expect(runtimes.map { |runtime| runtime["frame_label"] }).to all(match(/\A(Logtail::Integrations::Rack::HTTPEvents#)?call\z/))
  end

  it "log the single event with this middleware's call as its runtime context" do
    stack = Logtail::Integrations::Rack::HTTPContext.new(middleware)
    logs = capture_logs { with_collapse_into_single_event { stack.call mock_request } }

    runtime = logs.first["context"]["runtime"]
    expect(runtime["file"]).to end_with("lib/logtail-rack/http_events.rb")
    expect(runtime["frame_label"]).to match(/\A(Logtail::Integrations::Rack::HTTPEvents#)?call\z/)
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

  it "filter query string parameters with secrets in their names by default" do
    expect(described_class::DEFAULT_QUERY_STRING_FILTERS).to eq(%w[passw secret token _key crypt salt certificate otp ssn cvv cvc])
    expect(described_class.query_string_filters).to eq(described_class::DEFAULT_QUERY_STRING_FILTERS)

    logs = capture_logs { middleware.call request_with_query_string("password=hunter2&page=2&Api_Key=k1&ACCESS_TOKEN=t1&client_secret=s1&q=search") }

    query_string = logs.first["event"]["http_request_received"]["query_string"]
    expect(query_string).to eq("password=[FILTERED]&page=2&Api_Key=[FILTERED]&ACCESS_TOKEN=[FILTERED]&client_secret=[FILTERED]&q=search")
  end

  it "leave the rest of the query string byte for byte unchanged" do
    logs = capture_logs { middleware.call request_with_query_string("q=caf%C3%A9+au+lait&empty=&flag&a=1;b=2&x=y%26z&list[]=1&list[]=2&token=abc=def&=x&page=3") }

    query_string = logs.first["event"]["http_request_received"]["query_string"]
    expect(query_string).to eq("q=caf%C3%A9+au+lait&empty=&flag&a=1;b=2&x=y%26z&list[]=1&list[]=2&token=[FILTERED]&=x&page=3")
  end

  it "match the URL-decoded full name of nested query string parameters" do
    logs = capture_logs { middleware.call request_with_query_string("user[password]=p1&user%5Bpassword_confirmation%5D=p2&user[name]=Jane&pass%77ord=p3&%zz=1&%FFtoken=t1") }

    query_string = logs.first["event"]["http_request_received"]["query_string"]
    expect(query_string).to eq("user[password]=[FILTERED]&user%5Bpassword_confirmation%5D=[FILTERED]&user[name]=Jane&pass%77ord=[FILTERED]&%zz=1&%FFtoken=[FILTERED]")
  end

  it "filter the query string with custom query_string_filters" do
    logs = capture_logs do
      with_query_string_filters(["code", :page]) { middleware.call request_with_query_string("password=hunter2&page=2&Code=c1&q=search") }
    end

    query_string = logs.first["event"]["http_request_received"]["query_string"]
    expect(query_string).to eq("password=hunter2&page=[FILTERED]&Code=[FILTERED]&q=search")
  end

  it "filter the query string with Regexp query_string_filters, ignoring Procs" do
    filters = [/\Aq\z/, /sig/, ->(_name, value) { value.replace("changed") }]

    logs = capture_logs do
      with_query_string_filters(filters) { middleware.call request_with_query_string("q=1&query=2&Q=3&x_sig=abc&page=4") }
    end

    query_string = logs.first["event"]["http_request_received"]["query_string"]
    expect(query_string).to eq("q=[FILTERED]&query=2&Q=3&x_sig=[FILTERED]&page=4")
  end

  it "log the query string and URLs unfiltered when query_string_filters is set to an empty list" do
    app = ->(env) { [302, { "Location" => "https://example.com/next?token=t1" }, []] }
    request = request_with_query_string("password=hunter2&token=t1", "HTTP_REFERER" => "https://example.com/signup?password=hunter2")

    logs = capture_logs { with_query_string_filters([]) { described_class.new(app).call request } }

    expect(logs.first["event"]["http_request_received"]["query_string"]).to eq("password=hunter2&token=t1")
    expect(JSON.parse(logs.first["event"]["http_request_received"]["headers_json"])["Referer"]).to eq("https://example.com/signup?password=hunter2")
    expect(JSON.parse(logs.last["event"]["http_response_sent"]["headers_json"])["Location"]).to eq("https://example.com/next?token=t1")
  end

  it "filter the query of the URLs in the Referer request header and the Location response header" do
    app = ->(env) { [302, { "Location" => "https://example.com/next?token=t1&step=2#top", "Content-Type" => "text/plain" }, []] }
    request = Rack::MockRequest.env_for("https://example.com/test-page", "HTTP_REFERER" => "https://example.com/signup?password=hunter2&ref=ad")

    logs = capture_logs { described_class.new(app).call request }

    request_headers = JSON.parse(logs.first["event"]["http_request_received"]["headers_json"])
    expect(request_headers["Referer"]).to eq("https://example.com/signup?password=[FILTERED]&ref=ad")
    response_headers = JSON.parse(logs.last["event"]["http_response_sent"]["headers_json"])
    expect(response_headers).to eq({"Location" => "https://example.com/next?token=[FILTERED]&step=2#top", "Content-Type" => "text/plain"})
  end

  it "filter the query of the URL in a lower-case location response header" do
    app = ->(env) { [302, { "location" => "/next?client_secret=s1&step=2" }, []] }

    logs = capture_logs { described_class.new(app).call mock_request }

    response_headers = JSON.parse(logs.last["event"]["http_response_sent"]["headers_json"])
    expect(response_headers).to eq({"location" => "/next?client_secret=[FILTERED]&step=2"})
  end

  it "filter the query of the URL in the Location header of the single collapsed event" do
    app = ->(env) { [302, { "location" => "/next?token=t1&step=2" }, []] }
    stack = Logtail::Integrations::Rack::HTTPContext.new(described_class.new(app))

    logs = capture_logs { with_collapse_into_single_event { stack.call mock_request } }

    expect(logs.length).to eq(1)
    response_headers = JSON.parse(logs.first["event"]["http_response_sent"]["headers_json"])
    expect(response_headers).to eq({"location" => "/next?token=[FILTERED]&step=2"})
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

  def with_query_string_filters(filters, &blk)
    Logtail::Integrations::Rack::HTTPEvents.query_string_filters = filters

    blk.call
  ensure
    Logtail::Integrations::Rack::HTTPEvents.query_string_filters = Logtail::Integrations::Rack::HTTPEvents::DEFAULT_QUERY_STRING_FILTERS
  end

  # Sets QUERY_STRING directly, as some of the query strings aren't valid URIs
  def request_with_query_string(query_string, env = {})
    Rack::MockRequest.env_for("https://example.com/test-page", env).merge("QUERY_STRING" => query_string)
  end

  def with_collapse_into_single_event(&blk)
    Logtail::Integrations::Rack::HTTPEvents.collapse_into_single_event = true

    blk.call
  ensure
    Logtail::Integrations::Rack::HTTPEvents.collapse_into_single_event = false
  end
end
