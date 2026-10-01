require "spec_helper"
require "stringio"

RSpec.describe Logtail::Integrations::Rack::ErrorEvent do
  it "re-raise the app's exception when logging it raises" do
    app = ->(env) { raise "app failure" }
    logger = Logtail::Logger.new(StringIO.new)
    # Like the JSON formatter does with json 3 and ActiveSupport 8.0 or older
    logger.formatter = ->(*) { raise ArgumentError, "unknown keyword: :quirks_mode" }
    allow(Logtail::Config.instance).to receive(:logger).and_return(logger)

    expect { described_class.new(app).call(Rack::MockRequest.env_for("https://example.com/test-page")) }.to raise_error(RuntimeError, "app failure")
  end
end
