# frozen_string_literal: true

require "thor"

module KamalPullPreview
  class CLI < Thor
    # Ensure Thor exits with a non-zero status on failure.
    def self.exit_on_failure?
      true
    end

    desc "deploy", "Deploy a pull-request preview environment"
    option :pr,   required: true, type: :numeric, desc: "Pull request number"
    option :sha,  required: true, type: :string,  desc: "Git commit SHA"
    option :repo, required: true, type: :string,  desc: "owner/repo"
    def deploy
      pr_number = options[:pr].to_i
      sha       = options[:sha]
      repo      = options[:repo]

      url = Deployer.new.deploy(pr_number: pr_number, sha: sha, repo: repo)
      $stdout.puts "\e[32mPreview deployed: #{url}\e[0m"
    rescue DeployError, ConfigError => e
      $stderr.puts "\e[31mError: #{e.message}\e[0m"
      exit(1)
    end

    desc "remove", "Remove a pull-request preview environment"
    option :pr, required: true, type: :numeric, desc: "Pull request number"
    def remove
      pr_number = options[:pr].to_i

      Deployer.new.remove(pr_number: pr_number)
      $stdout.puts "\e[32mPreview for PR ##{pr_number} removed.\e[0m"
    rescue DeployError, ConfigError => e
      $stderr.puts "\e[31mError: #{e.message}\e[0m"
      exit(1)
    end

    desc "list", "List all active pull-request preview environments"
    def list
      rows = Cleaner.new.list_previews

      if rows.empty?
        $stdout.puts "No active previews."
        return
      end

      header = %w[PR SHA URL Status DeployedAt]
      table  = TTY::Table.new(header: header, rows: rows)
      $stdout.puts table.render(:unicode, padding: [0, 1])
    rescue DeployError, ConfigError => e
      $stderr.puts "\e[31mError: #{e.message}\e[0m"
      exit(1)
    end
  end
end
