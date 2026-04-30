# frozen_string_literal: true

require_relative "lib/kamal_pull_preview/version"

Gem::Specification.new do |spec|
  spec.name          = "kamal-pull-preview"
  spec.version       = KamalPullPreview::VERSION
  spec.authors       = ["cloudsbird"]
  spec.email         = []

  spec.summary       = "Pull request preview environments powered by Kamal 2.x"
  spec.description   = "kamal-pull-preview spins up per-PR preview environments " \
                       "using Kamal 2.x destination overrides, tracks state in a " \
                       "local SQLite database, and exposes a simple CLI."
  spec.homepage      = "https://github.com/cloudsbird/kamal-pull-preview"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"]   = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.glob("{exe,lib,templates}/**/*", File::FNM_DOTMATCH) +
               %w[LICENSE README.md kamal-pull-preview.gemspec]

  spec.bindir        = "exe"
  spec.executables   = ["kamal-pull-preview"]
  spec.require_paths = ["lib"]

  spec.add_dependency "thor",        "~> 1.3"
  spec.add_dependency "sqlite3",     "~> 1.7"
  spec.add_dependency "tty-table",   "~> 0.12"
  spec.add_dependency "tty-spinner", "~> 0.9"
  spec.add_dependency "octokit",     "~> 8.0"
end
