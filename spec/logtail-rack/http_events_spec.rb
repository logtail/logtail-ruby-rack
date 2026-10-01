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

  it "log a response with status 500 when the app raises, and re-raise the exception unchanged" do
    error = RuntimeError.new("boom")
    app = ->(env) { raise error }
    allow(Process).to receive(:clock_gettime).and_call_original
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(100.0, 100.0392345)

    logs = capture_logs do
      expect { described_class.new(app).call mock_request }.to raise_error(RuntimeError) { |raised| expect(raised).to be(error) }
    end

    expect(logs.map { |log| log["message"] }).to eq(['Started GET "/test-page"', "Completed 500 Internal Server Error in 39.2ms"])
    http_response_sent = logs.last["event"]["http_response_sent"]
    expect(http_response_sent["status"]).to eq(500)
    expect(http_response_sent["duration_ms"]).to eq(39.2)
    expect(http_response_sent["headers_json"]).to be_nil
    expect(http_response_sent["body"]).to be_nil
  end

  it "log a response with status 500 when the app raises an exception that is not a StandardError" do
    app = ->(env) { raise NotImplementedError, "not implemented" }

    logs = capture_logs do
      expect { described_class.new(app).call mock_request }.to raise_error(NotImplementedError, "not implemented")
    end

    expect(logs.last["event"]["http_response_sent"]["status"]).to eq(500)
  end

  it "log the status returned by status_for_exception when the app raises" do
    error = ArgumentError.new("no such record")
    app = ->(env) { raise error }
    resolved = []
    status_for_exception = lambda do |exception|
      resolved << exception
      404
    end

    logs = capture_logs do
      with_status_for_exception(status_for_exception) do
        expect { described_class.new(app).call mock_request }.to raise_error(ArgumentError) { |raised| expect(raised).to be(error) }
      end
    end

    expect(resolved.length).to eq(1)
    expect(resolved.first).to be(error)
    expect(logs.last["message"]).to match(/\ACompleted 404 Not Found in \d+\.\dms\z/)
    expect(logs.last["event"]["http_response_sent"]["status"]).to eq(404)
  end

  it "log the status 500 when status_for_exception raises itself" do
    error = RuntimeError.new("boom")
    app = ->(env) { raise error }

    logs = capture_logs do
      with_status_for_exception(->(_exception) { raise "status_for_exception failed" }) do
        expect { described_class.new(app).call mock_request }.to raise_error(RuntimeError) { |raised| expect(raised).to be(error) }
      end
    end

    expect(logs.last["event"]["http_response_sent"]["status"]).to eq(500)
  end

  it "log the single collapsed event with status 500 when the app raises" do
    app = ->(env) { raise "boom" }
    stack = Logtail::Integrations::Rack::HTTPContext.new(described_class.new(app))
    allow(Process).to receive(:clock_gettime).and_call_original
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(100.0, 100.0392345)

    logs = capture_logs do
      with_collapse_into_single_event do
        expect { stack.call mock_request }.to raise_error(RuntimeError, "boom")
      end
    end

    expect(logs.length).to eq(1)
    expect(logs.first["message"]).to eq("GET /test-page completed with 500 Internal Server Error in 39.2ms")
    expect(logs.first["event"]["http_response_sent"]["status"]).to eq(500)
  end

  it "re-raise the exception of the app when logging its response fails" do
    error = RuntimeError.new("boom")
    app = ->(env) { raise error }
    old_logger = Logtail::Config.instance.logger
    failing_logger = Logtail::Logger.new(StringIO.new)
    allow(failing_logger).to receive(:info).and_raise(IOError, "closed stream")
    Logtail::Config.instance.logger = failing_logger

    with_collapse_into_single_event do
      expect { described_class.new(app).call mock_request }.to raise_error(RuntimeError) { |raised| expect(raised).to be(error) }
    end
  ensure
    Logtail::Config.instance.logger = old_logger
  end

  it "resolve the status of an exception to 500 by default" do
    expect(described_class.status_for_exception).to be(described_class::DEFAULT_STATUS_FOR_EXCEPTION)
    expect(described_class.status_for_exception.call(RuntimeError.new("boom"))).to eq(500)
  end

  it "require status_for_exception to be callable" do
    expect { described_class.status_for_exception = 404 }.to raise_error(ArgumentError)
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

  def with_status_for_exception(status_for_exception, &blk)
    Logtail::Integrations::Rack::HTTPEvents.status_for_exception = status_for_exception

    blk.call
  ensure
    Logtail::Integrations::Rack::HTTPEvents.status_for_exception = Logtail::Integrations::Rack::HTTPEvents::DEFAULT_STATUS_FOR_EXCEPTION
  end
end
