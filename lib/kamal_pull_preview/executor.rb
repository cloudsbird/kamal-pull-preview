# frozen_string_literal: true

require "open3"
require "timeout"

module KamalPullPreview
  # Thin wrapper around shell execution so all subprocesses go through one place.
  module Executor
    DEFAULT_TIMEOUT = 600 # 10 minutes
    DEFAULT_RETRIES = 2

    class << self
      attr_accessor :dry_run

      # Log and run a shell command.
      # Accepts a single string or multiple arguments (preferred — avoids shell interpolation).
      # Raises DeployError if the command exits with a non-zero status.
      #
      # Options:
      #   :timeout  — max seconds to wait (default 600)
      #   :retries  — number of retries on failure (default 2)
      def execute(*args, timeout: DEFAULT_TIMEOUT, retries: DEFAULT_RETRIES)
        args = args.flatten
        cmd_str = args.join(" ")

        if dry_run
          logger.info("[dry-run] #{cmd_str}")
          return
        end

        logger.info("Executing: #{cmd_str}")

        attempt = 0
        begin
          _run_with_timeout(args, timeout)
        rescue DeployError => e
          attempt += 1
          if attempt <= retries
            backoff = 2**attempt
            logger.warn("Command failed, retrying in #{backoff}s (#{attempt}/#{retries}): #{cmd_str}")
            sleep(backoff)
            retry
          end
          raise e
        end
      end

      # Run a command and return its stdout as a String.
      # Accepts a single string or multiple arguments (preferred — avoids shell interpolation).
      # Does not raise on non-zero exit; callers must check the result.
      def capture(*args)
        args = args.flatten
        out, _status = Open3.capture2(*args)
        logger.debug("Captured: #{args.join(" ")}")
        out
      end

      # Run a command and return [stdout, Process::Status].
      # Accepts a single string or multiple arguments (preferred — avoids shell interpolation).
      # Does not raise on non-zero exit; callers must check the result.
      def capture2(*args)
        args = args.flatten
        out, status = Open3.capture2(*args)
        logger.debug("Captured (#{status.exitstatus}): #{args.join(" ")}")
        [out, status]
      end

      private

      def _run_with_timeout(args, timeout)
        Timeout.timeout(timeout, DeployError, "Command timed out after #{timeout}s: #{args.join(" ")}") do
          # Pass as an array so Ruby bypasses the shell (no shell injection risk).
          system(*args)
          status = Process.last_status

          if status.nil?
            raise DeployError, "Command not found or failed to execute: #{args.join(" ")}"
          end

          return if status.success?

          raise DeployError, "Command failed (exit #{status.exitstatus}): #{args.join(" ")}"
        end
      end

      def logger
        KamalPullPreview.logger
      end
    end
  end
end
