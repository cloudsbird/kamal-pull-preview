# frozen_string_literal: true

module KamalPullPreview
  # Computes PR-scoped accessories and injects environment variables.
  class AccessoriesManager
    # Maps accessory name patterns to the env var and URL template they produce.
    ENV_PATTERNS = [
      { pattern: /redis/i,        var: "REDIS_URL",    url: ->(host, port) { "redis://#{host}:#{port}/0" } },
      { pattern: /postgres|pg/i,  var: "DATABASE_URL", url: ->(host, port) { "postgres://postgres@#{host}:#{port}/preview" } },
      { pattern: /mysql/i,        var: "DATABASE_URL", url: ->(host, port) { "mysql2://root@#{host}:#{port}/preview" } },
    ].freeze

    # @param accessories_config [Hash]   name => raw config from deploy.yml
    # @param pr_number          [Integer]
    # @param host               [String] from kamal-pull-preview.yml
    # @param accessories_setting [Symbol, Array<String>] :auto | :none | ["redis", ...]
    def initialize(accessories_config:, pr_number:, host:, accessories_setting: :auto)
      @pr_number           = Integer(pr_number)
      @host                = host
      @accessories_setting = accessories_setting
      @accessories_config  = filter(accessories_config)
    end

    # Returns a hash suitable for merging into the destination YAML's `accessories:` key.
    # Each entry uses the PR-scoped name and overrides host and port.
    def scoped_accessories
      return {} if @accessories_config.empty?

      @accessories_config.each_with_object({}) do |(name, cfg), acc|
        scoped_name = scoped(name)
        original_port = port_from(cfg)
        pr_port = pr_port_for(original_port)

        entry = (cfg || {}).dup
        entry["host"] = @host
        entry["port"] = pr_port.to_s

        acc[scoped_name] = entry
      end
    end

    # Returns a hash of env var name => value for all known accessory types found.
    def env_overrides
      return {} if @accessories_config.empty?

      result = {}
      @accessories_config.each do |name, cfg|
        original_port = port_from(cfg)
        pr_port = pr_port_for(original_port)

        ENV_PATTERNS.each do |mapping|
          if name.match?(mapping[:pattern])
            result[mapping[:var]] = mapping[:url].call(@host, pr_port)
            break
          end
        end
      end
      result
    end

    # Boots all PR-scoped accessories via `kamal accessory boot`.
    def boot_all
      @accessories_config.each_key do |name|
        Executor.execute("kamal", "accessory", "boot", scoped(name), "-d", "pr-#{@pr_number}")
      end
    end

    # Removes all PR-scoped accessories via `kamal accessory remove`.
    def remove_all
      @accessories_config.each_key do |name|
        Executor.execute("kamal", "accessory", "remove", scoped(name), "-d", "pr-#{@pr_number}")
      end
    end

    private

    def scoped(name)
      "pr-#{@pr_number}-#{name}"
    end

    def pr_port_for(original_port)
      original_port + 10_000 + (@pr_number % 1_000)
    end

    def port_from(cfg)
      # Port may be specified as "6379" or as "6379:6379" (host:container mapping).
      # We extract the last segment to get the container port.
      raw = (cfg || {})["port"]
      raw.to_s.split(":").last.to_i.nonzero? || 0
    end

    def filter(raw_config)
      return {} if @accessories_setting == :none
      return {} unless raw_config.is_a?(Hash)

      if @accessories_setting.is_a?(Array)
        raw_config.select { |name, _| @accessories_setting.include?(name.to_s) }
      else
        raw_config
      end
    end
  end
end
