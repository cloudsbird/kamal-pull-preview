# frozen_string_literal: true

module KamalPullPreview
  # Orchestrates the full deploy / remove lifecycle for a PR preview.
  class Deployer
    def initialize(config: nil, state: nil, generator: nil, db_manager: nil)
      @config     = config     || Config.load
      @state      = state      || State.new
      @generator  = generator  || DestinationGenerator.new(config: @config)
      @db_manager = db_manager || DatabaseManager.new(config: @config)
    end

    # Deploy a preview for the given PR.
    # Returns the preview URL string on success.
    def deploy(pr_number:, sha:, repo: nil)
      check_capacity!

      @db_manager.setup(pr_number: pr_number)

      destination_file = @generator.generate(pr_number: pr_number)
      logger.info("Generated destination: #{destination_file}")
      logger.info("Using registry: #{@config.registry}")
      logger.info("Repo context: #{repo}") if repo

      # TODO: pass --version / image tag derived from sha when Kamal supports it
      Executor.execute("kamal", "deploy", "-d", "pr-#{Integer(pr_number)}")

      preview_url = "https://pr-#{pr_number}.#{@config.domain}"
      @state.upsert(pr_number: pr_number, sha: sha, preview_url: preview_url)

      preview_url
    end

    # Remove the preview for the given PR.
    # Cleans up both the Kamal destination and local state, even if one is missing.
    def remove(pr_number:)
      if destination_exists?(pr_number)
        Executor.execute("kamal", "remove", "-d", "pr-#{Integer(pr_number)}")
        @generator.cleanup(pr_number: pr_number)
      else
        logger.warn("No destination file found for PR ##{pr_number}, skipping kamal remove")
      end

      @db_manager.teardown(pr_number: pr_number)
      @state.remove(pr_number)
    rescue DeployError => e
      logger.error("Failed to remove PR ##{pr_number} from Kamal: #{e.message}")
      # Still attempt to clean up database and local state so we don't leak records
      begin
        @db_manager.teardown(pr_number: pr_number)
      rescue DbError => db_error
        logger.error("Failed to remove PR ##{pr_number} database: #{db_error.message}")
      end
      begin
        @state.remove(pr_number)
      rescue StateError => state_error
        logger.error("Failed to remove PR ##{pr_number} from state: #{state_error.message}")
      end
      raise e
    end

    private

    def check_capacity!
      active_count = @state.all.count { |r| r["status"] == "active" }
      if active_count >= @config.max_concurrent
        raise DeployError, "Maximum concurrent previews reached (#{@config.max_concurrent}). " \
                           "Remove an existing preview before deploying a new one."
      end
    end

    def destination_exists?(pr_number)
      File.exist?(File.join(DestinationGenerator::DESTINATIONS_DIR, "pr-#{pr_number}.yml"))
    end

    def logger
      KamalPullPreview.logger
    end
  end
end
