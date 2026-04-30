# frozen_string_literal: true

module KamalPullPreview
  # Orchestrates the full deploy / remove lifecycle for a PR preview.
  class Deployer
    def initialize(config: nil, state: nil, generator: nil)
      @config    = config    || Config.load
      @state     = state     || State.new
      @generator = generator || DestinationGenerator.new(config: @config)
    end

    # Deploy a preview for the given PR.
    # Returns the preview URL string on success.
    def deploy(pr_number:, sha:, repo: nil)
      check_capacity!

      destination_file = @generator.generate(pr_number: pr_number)
      $stdout.puts "Generated destination: #{destination_file}"

      # TODO: pass --version / image tag derived from sha when Kamal supports it
      Executor.execute("kamal", "deploy", "-d", "pr-#{Integer(pr_number)}")

      preview_url = "https://pr-#{pr_number}.#{@config.domain}"
      @state.upsert(pr_number: pr_number, sha: sha, preview_url: preview_url)

      preview_url
    end

    # Remove the preview for the given PR.
    def remove(pr_number:)
      raise DeployError, "No destination file found for PR ##{pr_number}. Was it ever deployed?" unless destination_exists?(pr_number)

      Executor.execute("kamal", "remove", "-d", "pr-#{Integer(pr_number)}")

      @generator.cleanup(pr_number: pr_number)
      @state.remove(pr_number)
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
  end
end
