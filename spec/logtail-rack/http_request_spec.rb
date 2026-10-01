# encoding: UTF-8

require "spec_helper"

RSpec.describe Logtail::Integrations::Rack::HTTPRequest do
  it "build headers_json when to_json raises, as it does with json 3 and ActiveSupport 8.0 or older" do
    # ActiveSupport up to 8.0 encodes a direct #to_json call itself and passes quirks_mode: to JSON.generate,
    # which json 3 rejects. JSON.generate calls #to_json with a JSON::State, which ActiveSupport hands to json.
    allow_any_instance_of(Hash).to receive(:to_json).and_wrap_original do |to_json, *args|
      raise ArgumentError, "unknown keyword: :quirks_mode" unless args.first.is_a?(JSON::State)
      to_json.call(*args)
    end

    http_request = described_class.new(headers: { "Content_Type" => "text/plain", "Accept" => "*/*" })

    expect(http_request.headers_json).to eq('{"Content_Type":"text/plain","Accept":"*/*"}')
  end
end
