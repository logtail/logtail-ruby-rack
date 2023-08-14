lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "logtail-rack/version"

Gem::Specification.new do |spec|
  spec.name          = "logtail-rack"
  spec.version       = Logtail::Integrations::Rack::VERSION
  spec.authors       = ["Logtail"]
  spec.email         = ["hi@logtail.com"]

  spec.summary       = %q{Logtail integration for Rack}
  spec.homepage      = "https://github.com/logtail/logtail-ruby-rack"
  spec.license       = "ISC"

  spec.required_ruby_version     = '>= 2.3'

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/logtail/logtail-ruby-rack"
  spec.metadata["changelog_uri"] = "https://github.com/logtail/logtail-ruby-rack/blob/master/README.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "logtail", "~> 0.1"
  spec.add_runtime_dependency "rack", ">= 1.2", "< 4.0"

  spec.add_development_dependency "bundler", ">= 0.0"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
