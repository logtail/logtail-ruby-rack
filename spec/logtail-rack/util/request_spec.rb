require "spec_helper"

RSpec.describe Logtail::Util::Request do
  describe ".headers" do
    it "should ignore symbol keys" do
      req = described_class.new({test: "value"})
      expect(req.headers).to eq({})
    end
  end

  describe ".request_id" do
    it "Returns Rack formatted http header" do
      req = described_class.new({"HTTP_X_REQUEST_ID" => "12345"})
      expect(req.request_id).to eq("12345")
    end
  end
end
