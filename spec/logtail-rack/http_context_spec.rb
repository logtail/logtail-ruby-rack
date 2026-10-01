require "spec_helper"

RSpec.describe Logtail::Integrations::Rack::HTTPContext do
  it "pass the request on without the HTTP context when reading the request raises" do
    http_contexts = []
    app = lambda { |env|
      http_contexts << Logtail::CurrentContext.fetch(:http, nil)
      [200, { "content-type" => "text/plain" }, ["hello"]]
    }
    # Rack::Request#host raises ArgumentError for invalid UTF-8 in a UTF-8 string
    request = Rack::MockRequest.env_for("https://example.com/test-page", "HTTP_X_FORWARDED_HOST" => "\xFF")

    response = described_class.new(app).call(request)

    expect(response).to eq([200, { "content-type" => "text/plain" }, ["hello"]])
    expect(http_contexts).to eq([nil])
  end
end
