# frozen_string_literal: true

require "thor"
require "fileutils"

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

    desc "init", "Scaffold kamal-pull-preview configuration files in the current directory"
    def init
      templates_dir = File.expand_path("../../../templates", __dir__)

      copy_template(
        File.join(templates_dir, "kamal-pull-preview.yml.erb"),
        "kamal-pull-preview.yml",
      )

      FileUtils.mkdir_p(".github/workflows")
      copy_template(
        File.join(templates_dir, "github-action.yml.erb"),
        ".github/workflows/pull-preview.yml",
      )

      $stdout.puts "\e[32mDone! Next steps:\e[0m"
      $stdout.puts "  1. Edit kamal-pull-preview.yml with your host, domain, and registry."
      $stdout.puts "  2. Add secrets referenced in .github/workflows/pull-preview.yml."
      $stdout.puts "  3. Commit both files and open a pull request to trigger a preview."
    end

    desc "cleanup", "Remove all expired pull-request preview environments"
    def cleanup
      count = Cleaner.new.cleanup_expired
      if count > 0
        $stdout.puts "\e[32mRemoved #{count} expired preview#{count == 1 ? "" : "s"}.\e[0m"
      else
        $stdout.puts "No expired previews found."
      end
    rescue DeployError, ConfigError => e
      $stderr.puts "\e[31mError: #{e.message}\e[0m"
      exit(1)
    end

    private

    def copy_template(src, dest)
      if File.exist?(dest)
        $stdout.puts "\e[33mSkipping #{dest} (already exists).\e[0m"
        return
      end

      require "erb"
      content = ERB.new(File.read(src)).result(binding)
      File.write(dest, content)
      $stdout.puts "\e[32mCreated #{dest}\e[0m"
    end
  end
end
