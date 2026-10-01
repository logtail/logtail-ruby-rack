source "https://rubygems.org"

gemspec

gem "base64" if RUBY_VERSION >= "3.4.0"
# No longer a default gem on Ruby 4.0 and TruffleRuby 40, and logtail 0.1.17 requires it undeclared
gem "logger"
# Rack 3 moved the session middlewares the tests use into this gem; its 1.x releases for older Racks are empty
gem "rack-session"
