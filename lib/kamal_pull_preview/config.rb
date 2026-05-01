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
      "accessories"          => "auto",
    }.freeze

    VALID_DB_STRATEGIES = %w[none sqlite shared_schema postgresql].freeze

    FIELDS = %i[
      host
      domain
      ttl_hours
      idle_stop_minutes
      max_concurrent
      db_strategy
      accessories
      registry
      pg_host
      pg_port
      pg_user
      pg_password
    ].freeze

    ConfigStruct = Struct.new(*FIELDS, keyword_init: true)

    # Load and validate config from the current directory.
    # Raises ConfigError if required keys are missing or invalid.
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

      validate_format!(data)

      ConfigStruct.new(
        host:               data["host"].to_s.strip,
        domain:             data["domain"].to_s.strip,
        ttl_hours:          data["ttl_hours"].to_i,
        idle_stop_minutes:  data["idle_stop_minutes"].to_i,
        max_concurrent:     data["max_concurrent"].to_i,
        db_strategy:        data["db_strategy"].to_s.strip,
        accessories:        normalize_accessories(data["accessories"]),
        registry:           data["registry"].to_s.strip,
        pg_host:            data["pg_host"].to_s.strip,
        pg_port:            (data["pg_port"] || 5432).to_i,
        pg_user:            data["pg_user"].to_s.strip,
        pg_password:        data["pg_password"].to_s,
      ).freeze
    end

    def self.validate_format!(data)
      %w[host domain].each do |key|
        value = data[key].to_s.strip
        if value.include?(" ")
          raise ConfigError, "Invalid #{key}: contains spaces (#{value})"
        end
      end

      registry = data["registry"].to_s.strip
      if registry.end_with?("/")
        raise ConfigError, "Invalid registry: should not end with a slash (#{registry})"
      end

      db_strategy = data["db_strategy"].to_s.strip
      unless VALID_DB_STRATEGIES.include?(db_strategy)
        raise ConfigError,
              "Invalid db_strategy: '#{db_strategy}'. " \
              "Must be one of: #{VALID_DB_STRATEGIES.join(', ')}"
      end

      if db_strategy == "postgresql"
        %w[pg_host pg_user pg_password].each do |key|
          if data[key].nil? || data[key].to_s.empty?
            raise ConfigError, "Missing required config key for postgresql strategy: #{key}"
          end
        end
      end
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

        # Database strategy: "none" | "sqlite" | "shared_schema" | "postgresql" (default: "none")
        db_strategy: "none"

        # Accessories strategy: "auto" (read from config/deploy.yml) | "none" | list (default: "auto")
        # accessories: auto
        # accessories: none
        # accessories:
        #   - redis
        #   - postgres

        # PostgreSQL settings (only required when db_strategy is "postgresql")
        # pg_host: "db.example.com"
        # pg_port: 5432
        # pg_user: "preview_admin"
        # pg_password: "secret"
      YAML
    end

    def self.normalize_accessories(value)
      case value
      when nil, "auto"
        :auto
      when "none"
        :none
      when Array
        value.map(&:to_s)
      else
        :auto
      end
    end
  end
end
