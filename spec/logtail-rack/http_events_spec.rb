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
