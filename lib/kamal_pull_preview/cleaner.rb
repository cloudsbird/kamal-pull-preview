# frozen_string_literal: true

module KamalPullPreview
  # Housekeeping: expire old previews and provide formatted preview lists.
  class Cleaner
    def initialize(state: nil, deployer: nil)
      @state    = state    || State.new
      @deployer = deployer || Deployer.new(state: @state)
    end

    # Remove all previews that have exceeded the configured TTL.
    # Returns the number of previews cleaned up.
    def cleanup_expired(ttl_hours: nil)
      config    = Config.load
      ttl_hours ||= config.ttl_hours

      expired = @state.expired(ttl_hours: ttl_hours)
      expired.each do |preview|
        @deployer.remove(pr_number: preview["pr_number"])
      rescue DeployError => e
        logger.warn("Could not remove PR ##{preview["pr_number"]}: #{e.message}")
      end

      expired.size
    end

    # Return preview data formatted as rows for TTY::Table.
    # Columns: PR, SHA, URL, Status, DeployedAt
    def list_previews
      @state.all.map do |r|
        [
          r["pr_number"],
          r["sha"]&.slice(0, 7),
          r["preview_url"],
          r["status"],
          r["deployed_at"],
        ]
      end
    end

    private

    def logger
      KamalPullPreview.logger
    end
  end
end
