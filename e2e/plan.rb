# Prints the job matrix of the E2E workflow (.github/workflows/e2e.yml) as JSON.
#
#   ruby e2e/plan.rb [--leg all|floor|rack2|latest|canary] [--ruby <version>] [--rack <version>] [--logtail <version>] [--source checkout|rubygems]
#
# floor   Ruby 2.7 with the oldest rack and logtail releases the gemspec allows that run the example (see FLOOR_*)
# rack2   Ruby 3.2 with the newest Rack 2 and the newest logtail release
# latest  the newest stable Ruby that ruby/setup-ruby installs, with the newest rack and logtail releases. Bundler
#         failing to install them, say a Rack 4 that the gemspec's "< 4.0" excludes, fails the job.
# canary  ruby-head with rack's main branch and the newest logtail release
#
# --ruby, --rack and --logtail replace the planned version of every leg that runs with one exact version, which is
# how a run bisects a failure to one release. --source is copied into every entry: checkout installs the gem built
# from this checkout, rubygems the newest logtail-rack release, which is then the client version planned.
#
# Standard library only, so the plan job needs nothing but a Ruby.
require "json"
require "net/http"
require "optparse"
require "rubygems"

ROOT = File.expand_path("..", __dir__)
GEMSPEC = File.join(ROOT, "logtail-ruby-rack.gemspec")
# What the ruby/setup-ruby@v1 that the test job uses can install.
SETUP_RUBY_VERSIONS_URL = "https://raw.githubusercontent.com/ruby/setup-ruby/v1/ruby-builder-versions.json"
RUBYGEMS_VERSIONS_URL = "https://rubygems.org/api/v1/versions/%s.json"
LEGS = %w[floor rack2 latest canary].freeze
# Job names become artifact names (e2e-summary-<job name>), which must not contain any of these.
NOT_IN_NAMES = ':"<>|*?/\\'.chars.freeze

# The gemspec allows Ruby 2.3, but main.yml tests Rack 1, the oldest the gemspec allows, on Ruby 2.7 only.
FLOOR_RUBY = "2.7".freeze
# The gemspec allows logtail 0.1.0, but releases before 0.1.14 have no ingesting_host option, which the example and
# the README pass, and 0.1.14 calls Rails' String#present? and fails without Rails. Remove this once the gemspec
# requires logtail >= 0.1.15.
FLOOR_LOGTAIL = Gem::Version.new("0.1.15")
# The other Ruby main.yml tests the Rack pins on.
RACK2_RUBY = "3.2".freeze

def fetch_json(url, attempts: 3)
  error = nil
  attempts.times do |attempt|
    # A registry hiccup at schedule time should not file a Linear issue, so the lookup is retried.
    sleep 10 if attempt > 0
    begin
      response = Net::HTTP.get_response(URI(url))
      return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

      error = "HTTP #{response.code}"
    rescue StandardError => e
      error = e.message
    end
  end
  abort "GET #{url} failed #{attempts} times, last: #{error}"
end

# Every release of a gem on rubygems.org, without pre-releases, oldest first.
def releases(name)
  @releases ||= {}
  @releases[name] ||= fetch_json(format(RUBYGEMS_VERSIONS_URL, name))
    .reject { |version| version["prerelease"] }
    .map { |version| Gem::Version.new(version["number"]) }
    .uniq.sort
end

def newest_release(name, requirement = Gem::Requirement.default)
  releases(name).select { |version| requirement.satisfied_by?(version) }.max ||
    abort("rubygems.org lists no #{name} release matching #{requirement}")
end

def lowest_release(name, requirement)
  releases(name).find { |version| requirement.satisfied_by?(version) } ||
    abort("rubygems.org lists no #{name} release matching #{requirement}")
end

def newest_stable_ruby
  fetch_json(SETUP_RUBY_VERSIONS_URL).fetch("ruby")
    .grep(/\A\d+\.\d+\.\d+\z/)
    .max_by { |version| Gem::Version.new(version) }
end

def dependency(spec, name)
  spec.runtime_dependencies.find { |dependency| dependency.name == name } ||
    abort("#{File.basename(GEMSPEC)} declares no #{name} dependency")
end

def plan(leg, spec, ruby: nil, rack: nil, logtail: nil)
  case leg
  when "floor"
    ruby ||= FLOOR_RUBY
    rack ||= lowest_release("rack", dependency(spec, "rack").requirement).to_s
    logtail ||= [lowest_release("logtail", dependency(spec, "logtail").requirement), FLOOR_LOGTAIL].max.to_s
  when "rack2"
    ruby ||= RACK2_RUBY
    rack ||= newest_release("rack", Gem::Requirement.new("~> 2.0")).to_s
  when "latest"
    ruby ||= newest_stable_ruby
    rack ||= newest_release("rack").to_s
  when "canary"
    ruby ||= "head"
    rack ||= "main"
  end
  logtail ||= newest_release("logtail").to_s

  name = "#{leg} (Ruby #{ruby}, Rack #{rack}, logtail #{logtail})"
  abort "job name #{name.inspect} contains one of #{NOT_IN_NAMES.join}, which artifact names do not allow" if (name.chars & NOT_IN_NAMES).any?
  {
    leg: leg,
    name: name,
    ruby: ruby,
    rack: rack,
    logtail: logtail,
    # The floor and rack2 run on the oldest Ubuntu image GitHub offers, the other legs follow ubuntu-latest.
    runner: %w[floor rack2].include?(leg) ? "ubuntu-24.04" : "ubuntu-latest",
  }
end

options = { leg: "all", source: "checkout" }
OptionParser.new do |parser|
  parser.on("--leg LEG", ["all", *LEGS])
  parser.on("--ruby VERSION")
  parser.on("--rack VERSION")
  parser.on("--logtail VERSION")
  parser.on("--source SOURCE", %w[checkout rubygems])
end.parse!(into: options)
overrides = options.slice(:ruby, :rack, :logtail).transform_values(&:strip).reject { |_name, version| version.empty? }

spec = Gem::Specification.load(GEMSPEC) || abort("could not load #{GEMSPEC}")
client = options[:source] == "rubygems" ? newest_release("logtail-rack").to_s : spec.version.to_s
legs = options[:leg] == "all" ? LEGS : [options[:leg]]
puts JSON.generate(legs.map { |leg| plan(leg, spec, **overrides).merge(source: options[:source], client: client) })
