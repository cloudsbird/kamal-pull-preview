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
    VALID_DB_SEED_FORMATS = %w[auto custom plain directory].freeze

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
      db_seed
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
        db_seed:            normalize_db_seed(data["db_seed"]),
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

      validate_db_seed!(data["db_seed"]) if data["db_seed"]
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

    def self.normalize_db_seed(value)
      return nil unless value.is_a?(Hash)

      {
        "source"       => value["source"].to_s,
        "format"       => (value["format"] || "auto").to_s,
        "required"     => value.key?("required") ? !!value["required"] : false,
        "table_check"  => value.key?("table_check") ? !!value["table_check"] : true,
      }.freeze
    end

    def self.validate_db_seed!(raw)
      unless raw.is_a?(Hash)
        raise ConfigError, "Invalid db_seed: must be a mapping with at least a 'source' key"
      end

      source = raw["source"].to_s.strip
      if source.empty?
        raise ConfigError, "Invalid db_seed: 'source' must be a non-empty string"
      end

      fmt = (raw["format"] || "auto").to_s
      unless VALID_DB_SEED_FORMATS.include?(fmt)
        raise ConfigError,
              "Invalid db_seed format: '#{fmt}'. " \
              "Must be one of: #{VALID_DB_SEED_FORMATS.join(', ')}"
      end
    end
  end
end
