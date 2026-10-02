require "spec_helper"
require "rack/session/cookie"
require "rack/session/pool"

RSpec.describe Logtail::Integrations::Rack::SessionContext do
  [Rack::Session::Cookie, Rack::Session::Pool].each do |session_store|
    it "log the private id of a #{session_store.name} session as a String", :aggregate_failures do
      skip "Rack::Session::SessionId is new in Rack 1.6.12 and 2.0.8" unless defined?(Rack::Session::SessionId)
      # Makes the session store generate a known session id
      secure_random = Object.new
      def secure_random.hex(_length)
        "5e55102d0f1c4a6b9e2d7c8a1b3f6e90"
      end
      app = Rack::Builder.new do
        use session_store, secret: "x" * 64, secure_random: secure_random
        use Logtail::Integrations::Rack::SessionContext
        run lambda { |env|
          env["rack.session"]["visits"] = 1
          Logtail::Config.instance.logger.info("inside the app")
          [200, {}, ["ok"]]
        }
      end.to_app
      request = Rack::MockRequest.new(app)

      entries = capture_log_entries do
        session_cookie = Array(request.get("/").headers["Set-Cookie"]).first.split(";").first
        request.get("/", "HTTP_COOKIE" => session_cookie)
      end

      # The first request has no session cookie yet. The private id is "2::" and the SHA-256 digest of the
      # session id, the key Rack's server-side stores use. The session id is the cookie value of those stores.
      expect(entries.map { |entry| entry.context_snapshot[:session] }).to eq([nil, { id: "2::5ea0adef81b3967d06c0bfc9021a8d4657afbe5a960a41977b99a3e0739e9087" }])
      expect { entries.map(&:to_hash).to_msgpack }.not_to raise_error
    end
  end

  it "log a String session id as it is" do
    app = lambda { |env|
      Logtail::Config.instance.logger.info("inside the app")
      [200, {}, ["ok"]]
    }
    env = Rack::MockRequest.env_for("/", "rack.session" => Struct.new(:id).new("plain-session-id"))

    entries = capture_log_entries { described_class.new(app).call(env) }

    expect(entries.map { |entry| entry.context_snapshot[:session] }).to eq([{ id: "plain-session-id" }])
  end

  # Collects the LogEntry objects the way the HTTP log device receives them, before MessagePack encodes them
  def capture_log_entries(&blk)
    old_logger = Logtail::Config.instance.logger

    entries = []
    device = Object.new
    device.define_singleton_method(:write) { |entry| entries << entry }
    device.define_singleton_method(:close) {}
    logger = Logtail::Logger.new(device)
    logger.formatter = Logtail::Logger::PassThroughFormatter.new
    Logtail::Config.instance.logger = logger

    blk.call

    entries
  ensure
    Logtail::Config.instance.logger = old_logger
  end
end
