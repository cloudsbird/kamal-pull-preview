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

    desc "init", "Generate kamal-pull-preview.yml and GitHub Actions workflow in the current project"
    def init
      config_dest   = File.join(Dir.pwd, "kamal-pull-preview.yml")
      workflow_dir  = File.join(Dir.pwd, ".github", "workflows")
      workflow_dest = File.join(workflow_dir, "pull-preview.yml")

      config_template  = File.join(__dir__, "..", "..", "templates", "kamal-pull-preview.yml.erb")
      workflow_template = File.join(__dir__, "..", "..", "templates", "github-action.yml.erb")

      _write_template(src: config_template,  dest: config_dest,   label: "kamal-pull-preview.yml")
      FileUtils.mkdir_p(workflow_dir)
      _write_template(src: workflow_template, dest: workflow_dest, label: ".github/workflows/pull-preview.yml")

      puts "\n\e[32mDone!\e[0m Next steps:"
      puts "  1. Edit kamal-pull-preview.yml with your host, domain, and registry"
      puts "  2. Commit .github/workflows/pull-preview.yml"
      puts "  3. Set KAMAL_REGISTRY_PASSWORD in your repo secrets"
    end

    desc "cleanup", "Remove all previews that have exceeded their TTL"
    def cleanup
      removed = Cleaner.new.cleanup_expired

      if removed.zero?
        puts "No expired previews found."
      else
        puts "\e[32mRemoved #{removed} expired preview(s).\e[0m"
      end
    rescue ConfigError => e
      puts "\e[31mConfig error: #{e.message}\e[0m"
      exit 1
    rescue DeployError => e
      puts "\e[31mDeploy error: #{e.message}\e[0m"
      exit 1
    end

    private

    def _write_template(src:, dest:, label:)
      if File.exist?(dest)
        puts "\e[33mSkipped\e[0m  #{label} (already exists)"
      else
        require "erb"
        content = ERB.new(File.read(src)).result(binding)
        File.write(dest, content)
        puts "\e[32mCreated\e[0m  #{label}"
      end
    end
  end
end
