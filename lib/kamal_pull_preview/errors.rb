# frozen_string_literal: true

module KamalPullPreview
  # Raised when the kamal-pull-preview.yml config is missing or invalid.
  class ConfigError < StandardError; end

  # Raised when a Kamal deploy or remove command fails.
  class DeployError < StandardError; end

  # Raised when the SQLite state store encounters an inconsistency.
  class StateError < StandardError; end
end
