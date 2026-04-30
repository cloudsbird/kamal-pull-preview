# frozen_string_literal: true

require "logger"
require "fileutils"

module KamalPullPreview
  # Structured logger that writes to both $stdout and a log file.
  # A simple singleton accessible via KamalPullPreview.logger
  class Log
    LOG_DIR  = File.join(Dir.home, ".kamal-pull-preview")
    LOG_PATH = File.join(LOG_DIR, "kamal-pull-preview.log")

    class << self
      def instance
        @instance ||= begin
          FileUtils.mkdir_p(LOG_DIR)
          logger = Logger.new(LOG_PATH)
          logger.level = Logger::INFO
          logger.formatter = proc do |severity, datetime, _progname, msg|
            "[#{datetime.utc.iso8601}] #{severity}: #{msg}\n"
          end
          logger
        end
      end

      %i[debug info warn error fatal].each do |level|
        define_method(level) do |*args, &block|
          msg = block ? block.call : args.join(" ")
          instance.public_send(level, msg)
          # Also mirror INFO+ to stdout for CLI visibility
          $stdout.puts(msg) if %i[info warn error fatal].include?(level)
        end
      end
    end
  end

  def self.logger
    Log
  end
end
