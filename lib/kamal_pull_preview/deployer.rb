# frozen_string_literal: true

module KamalPullPreview
  # Orchestrates the full deploy / remove lifecycle for a PR preview.
  class Deployer
    def initialize(config: nil, state: nil, generator: nil, db_manager: nil)
      @config     = config     || Config.load
      @state      = state      || State.new
      @db_manager = db_manager || DatabaseManager.new(config: @config)
      @generator  = generator  || DestinationGenerator.new(config: @config, db_manager: @db_manager)
    end

    # Deploy a preview for the given PR.
    # Returns the preview URL string on success.
    def deploy(pr_number:, sha:, repo: nil)
      validate_pr_number!(pr_number)
      check_capacity!

      @db_manager.setup(pr_number: pr_number)

      destination_file = @generator.generate(pr_number: pr_number)
      logger.info("Generated destination: #{destination_file}")
      logger.info("Using registry: #{@config.registry}")
      logger.info("Repo context: #{repo}") if repo

      begin
        accessories_manager_for(pr_number).boot_all

        if @config.respond_to?(:db_seed) && @config.db_seed
          @db_manager.restore_seed(
            pr_number:        pr_number,
            destination_type: seed_destination_type,
          )
        end

        Executor.execute("kamal", "deploy", "-d", "pr-#{Integer(pr_number)}")
      rescue StandardError => e
        begin
          accessories_manager_for(pr_number).remove_all
        rescue StandardError => cleanup_err
          logger.error("Failed to remove accessories for PR ##{pr_number}: #{cleanup_err.message}")
        end
        begin
          @db_manager.teardown(pr_number: pr_number)
        rescue DbError => db_err
          logger.error("Failed to teardown database for PR ##{pr_number}: #{db_err.message}")
        end
        @generator.cleanup(pr_number: pr_number)
        raise e
      end

      preview_url = "https://pr-#{pr_number}.#{@config.domain}"
      @state.upsert(pr_number: pr_number, sha: sha, preview_url: preview_url)

      preview_url
    end

    # Remove the preview for the given PR.
    # Cleans up both the Kamal destination and local state, even if one is missing.
    def remove(pr_number:)
      validate_pr_number!(pr_number)
      if destination_exists?(pr_number)
        Executor.execute("kamal", "remove", "-d", "pr-#{Integer(pr_number)}")
        accessories_manager_for(pr_number).remove_all
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
    ensure
      @generator.cleanup(pr_number: pr_number)
    end

    private

    def validate_pr_number!(pr_number)
      num = Integer(pr_number)
      raise DeployError, "PR number must be a positive integer, got: #{pr_number.inspect}" unless num.positive?
    rescue ArgumentError
      raise DeployError, "PR number must be a positive integer, got: #{pr_number.inspect}"
    end

    def accessories_manager_for(pr_number)
      reader = DeployConfigReader.new
      AccessoriesManager.new(
        accessories_config:  reader.accessories,
        pr_number:           pr_number,
        host:                @config.host,
        accessories_setting: @config.accessories,
      )
    end

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

    def seed_destination_type
      case @config.db_strategy
      when "shared_schema" then :shared_schema
      when "postgresql"    then :accessory_postgres
      when "sqlite"        then :sqlite
      else                      :none
      end
    end

    def logger
      KamalPullPreview.logger
    end
  end
end
