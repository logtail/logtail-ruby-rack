require "spec_helper"

RSpec.describe Logtail::Integrations::Rack::UserContext do
  it "pass the request on without the user context when reading the user raises" do
    user = Object.new
    def user.id
      1
    end
    # Like an ActiveRecord user loaded without its email column
    def user.email
      raise NoMethodError, "missing attribute 'email' for User"
    end
    user_contexts = []
    app = lambda { |env|
      user_contexts << Logtail::CurrentContext.fetch(:user, nil)
      [200, { "content-type" => "text/plain" }, ["hello"]]
    }
    request = Rack::MockRequest.env_for("https://example.com/test-page", "warden" => double(user: user))

    response = described_class.new(app).call(request)

    expect(response).to eq([200, { "content-type" => "text/plain" }, ["hello"]])
    expect(user_contexts).to eq([nil])
  end
end
