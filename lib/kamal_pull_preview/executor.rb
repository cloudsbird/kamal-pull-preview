# frozen_string_literal: true

require "open3"

module KamalPullPreview
  # Thin wrapper around shell execution so all subprocesses go through one place.
  module Executor
    # Log and run a shell command.
    # Accepts a single string or multiple arguments (preferred — avoids shell interpolation).
    # Raises DeployError if the command exits with a non-zero status.
    def self.execute(*args)
      args = args.flatten
      $stdout.puts "\e[36m$ #{args.join(" ")}\e[0m"
      # Pass as an array so Ruby bypasses the shell (no shell injection risk).
      system(*args)
      status = Process.last_status
      raise DeployError, "Command failed (exit #{status.exitstatus}): #{args.join(" ")}" unless status.success?
    end

    # Run a command and return its stdout as a String.
    # Accepts a single string or multiple arguments (preferred — avoids shell interpolation).
    # Does not raise on non-zero exit; callers must check the result.
    def self.capture(*args)
      args = args.flatten
      out, _status = Open3.capture2(*args)
      out
    end
  end
end
