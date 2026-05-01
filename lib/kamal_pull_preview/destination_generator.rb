# frozen_string_literal: true

require "fileutils"
require "yaml"

module KamalPullPreview
  # Generates Kamal 2.x destination override files for each pull-request preview.
  class DestinationGenerator
    DESTINATIONS_DIR = ".kamal/destinations"

    def initialize(config: nil, deploy_config_reader: nil, accessories_manager: nil)
      @config = config || Config.load
      @deploy_config_reader = deploy_config_reader
      @accessories_manager  = accessories_manager
    end

    # Write the destination YAML for the given PR number.
    # Returns the path to the generated file.
    def generate(pr_number:)
      FileUtils.mkdir_p(DESTINATIONS_DIR)
      path = destination_path(pr_number)

      reader   = accessories_reader
      manager  = build_accessories_manager(pr_number, reader)

      File.write(path, render(pr_number, reader, manager))

      path
    end

    # Delete the destination YAML for the given PR number.
    def cleanup(pr_number:)
      path = destination_path(pr_number)
      FileUtils.rm_f(path)
    end

    private

    def destination_path(pr_number)
      File.join(DESTINATIONS_DIR, "pr-#{pr_number}.yml")
    end

    def accessories_reader
      @deploy_config_reader || DeployConfigReader.new
    end

    def build_accessories_manager(pr_number, reader)
      return @accessories_manager if @accessories_manager

      AccessoriesManager.new(
        accessories_config:   reader.accessories,
        pr_number:            pr_number,
        host:                 @config.host,
        accessories_setting:  @config.accessories,
      )
    end

    # Renders the Kamal 2.x destination override content.
    def render(pr_number, reader, manager)
      env_vars = {
        "PULL_PREVIEW" => "true",
        "PR_NUMBER"    => pr_number.to_s,
      }

      if @config.db_strategy == "postgresql"
        db_url = DatabaseManager.new(config: @config).database_url(pr_number: pr_number)
        env_vars["DATABASE_URL"] = db_url if db_url
      end

      env_vars.merge!(manager.env_overrides)

      data = {}

      # Build servers section from deploy.yml roles
      roles      = reader.server_roles
      servers_h  = build_servers_hash(roles)
      data["servers"] = servers_h

      data["proxy"] = { "host" => "pr-#{pr_number}.#{@config.domain}" }

      scoped = manager.scoped_accessories
      data["accessories"] = scoped unless scoped.empty?

      data["env"] = { "clear" => env_vars }

      YAML.dump(data)
    end

    def build_servers_hash(roles)
      roles.each_with_object({}) do |role, h|
        if role == "web"
          h["web"] = [@config.host]
        else
          h[role] = { "hosts" => [@config.host] }
        end
      end
    end
  end
end
