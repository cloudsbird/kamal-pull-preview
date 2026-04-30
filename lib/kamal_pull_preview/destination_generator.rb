# frozen_string_literal: true

require "fileutils"

module KamalPullPreview
  # Generates Kamal 2.x destination override files for each pull-request preview.
  class DestinationGenerator
    DESTINATIONS_DIR = ".kamal/destinations"

    def initialize(config: nil)
      @config = config || Config.load
    end

    # Write the destination YAML for the given PR number.
    # Returns the path to the generated file.
    def generate(pr_number:)
      FileUtils.mkdir_p(DESTINATIONS_DIR)
      path = destination_path(pr_number)

      File.write(path, render(pr_number))

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

    # Renders the Kamal 2.x destination override content.
    def render(pr_number)
      <<~YAML
        servers:
          web:
            - #{@config.host}
        proxy:
          host: pr-#{pr_number}.#{@config.domain}
        env:
          clear:
            PULL_PREVIEW: "true"
            PR_NUMBER: "#{pr_number}"
      YAML
    end
  end
end
