# frozen_string_literal: true

require "yaml"

module KamalPullPreview
  # Loads and validates kamal-pull-preview.yml from the current working directory.
  class Config
    CONFIG_FILE = "kamal-pull-preview.yml"

    DEFAULTS = {
      "ttl_hours"            => 48,
      "idle_stop_minutes"    => 240,
      "max_concurrent"       => 15,
      "db_strategy"          => "none",
    }.freeze

    FIELDS = %i[
      host
      domain
      ttl_hours
      idle_stop_minutes
      max_concurrent
      db_strategy
      registry
    ].freeze

    ConfigStruct = Struct.new(*FIELDS, keyword_init: true)

    # Load and validate config from the current directory.
    # Raises ConfigError if required keys are missing.
    def self.load(path: CONFIG_FILE)
      raw = begin
        YAML.safe_load(File.read(path), permitted_classes: []) || {}
      rescue Errno::ENOENT
        raise ConfigError, "Config file not found: #{path}. " \
                           "Run `kamal-pull-preview init` or create #{path} manually."
      rescue Psych::SyntaxError => e
        raise ConfigError, "YAML syntax error in #{path}: #{e.message}"
      end

      data = DEFAULTS.merge(raw.reject { |_, v| v.nil? })

      %w[host domain registry].each do |key|
        raise ConfigError, "Missing required config key: #{key}" if data[key].nil? || data[key].to_s.empty?
      end

      ConfigStruct.new(
        host:               data["host"],
        domain:             data["domain"],
        ttl_hours:          data["ttl_hours"].to_i,
        idle_stop_minutes:  data["idle_stop_minutes"].to_i,
        max_concurrent:     data["max_concurrent"].to_i,
        db_strategy:        data["db_strategy"],
        registry:           data["registry"],
      ).freeze
    end

    # Returns an example YAML string that can be written to kamal-pull-preview.yml.
    def self.example
      <<~YAML
        # Copy this to your project root as kamal-pull-preview.yml

        # SSH host where preview containers will be deployed (required)
        host: "preview.example.com"

        # Base domain for preview URLs, e.g. pr-42.preview.example.com (required)
        domain: "preview.example.com"

        # Docker registry prefix used by Kamal (required)
        registry: "registry.example.com/myorg/myapp"

        # How many hours before an inactive preview is considered expired (default: 48)
        ttl_hours: 48

        # Minutes of inactivity before the container is stopped (default: 240)
        idle_stop_minutes: 240

        # Maximum number of concurrently running previews (default: 15)
        max_concurrent: 15

        # Database strategy: "none" | "sqlite" | "shared_schema" (default: "none")
        db_strategy: "none"
      YAML
    end
  end
end
