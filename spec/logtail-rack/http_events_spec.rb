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

  def with_collapse_into_single_event(&blk)
    Logtail::Integrations::Rack::HTTPEvents.collapse_into_single_event = true

    blk.call
  ensure
    Logtail::Integrations::Rack::HTTPEvents.collapse_into_single_event = false
  end
end
