# frozen_string_literal: true

require "yaml"

module KamalPullPreview
  # Parses the app's config/deploy.yml to discover accessories and server roles.
  class DeployConfigReader
    DEFAULT_PATH = "config/deploy.yml"

    def initialize(path: DEFAULT_PATH)
      @path = path
      @data = load_data
    end

    # Returns a hash of accessory name => config (raw from deploy.yml), or {} if none.
    def accessories
      @data.fetch("accessories", {}) || {}
    end

    # Returns an array of role name strings, e.g. ["web", "sidekiq"].
    # Falls back to ["web"] if servers is absent or not a hash.
    def server_roles
      servers = @data["servers"]
      return ["web"] unless servers.is_a?(Hash) && !servers.empty?

      servers.keys.map(&:to_s)
    end

    private

    def load_data
      YAML.safe_load(File.read(@path), permitted_classes: []) || {}
    rescue Errno::ENOENT
      {}
    rescue Psych::SyntaxError
      {}
    end
  end
end
