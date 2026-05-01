# frozen_string_literal: true

require "open3"
require "tempfile"

module KamalPullPreview
  # Downloads or locates a database dump from various source types:
  # s3://, https://, http://, bare file path, or cmd: prefix.
  class DumpFetcher
    def initialize(source:, format: "auto")
      @source = source.to_s
      @format = format.to_s
    end

    # Returns true if the dump source is reachable/available.
    def available?
      case source_type
      when :s3
        _, status = Open3.capture2e("aws", "s3", "ls", @source)
        status.success?
      when :https, :http
        _, status = Open3.capture2e("curl", "-fsI", "--max-time", "10", @source)
        status.success?
      when :file
        File.exist?(@source)
      when :cmd
        true
      else
        false
      end
    end

    # Fetches the dump and returns a path to a local file containing the data.
    # For file sources, returns the original path directly.
    # Fetches the dump and returns a path to a local file containing the data.
    # For file sources, returns the original path directly.
    # For all other sources, a Tempfile is created; callers should treat the
    # returned path as temporary and not assume it persists across process restarts.
    def fetch
      case source_type
      when :s3
        tmp = Tempfile.new(["kpp-dump", ".dump"])
        tmp.close
        Executor.execute("aws", "s3", "cp", @source, tmp.path)
        tmp.path
      when :https, :http
        tmp = Tempfile.new(["kpp-dump", ".dump"])
        tmp.close
        Executor.execute("curl", "-fsSL", "-o", tmp.path, @source)
        tmp.path
      when :file
        @source
      when :cmd
        cmd = @source.sub(/\Acmd:/, "").strip
        tmp = Tempfile.new(["kpp-dump", ".dump"])
        out, status = Open3.capture2(cmd)
        raise DbError, "Seed command failed: #{cmd}" unless status.success?

        tmp.write(out)
        tmp.flush
        tmp.close
        tmp.path
      else
        raise DbError, "Unsupported source type for: #{@source}"
      end
    end

    # Inspects magic bytes (or directory status) to detect the dump format.
    # Returns one of: "custom", "plain", "directory", or "auto".
    def detect_format
      return "directory" if Dir.exist?(@source)

      path = source_type == :file ? @source : nil
      return @format unless path && @format == "auto"

      begin
        header = File.binread(path, 8).force_encoding("BINARY")
        if header.start_with?("PGDMP")
          "custom"
        elsif header.start_with?("--") || header.start_with?("BEGIN")
          "plain"
        else
          "plain"
        end
      rescue StandardError
        "plain"
      end
    end

    private

    def source_type
      if @source.start_with?("s3://")
        :s3
      elsif @source.start_with?("https://")
        :https
      elsif @source.start_with?("http://")
        :http
      elsif @source.start_with?("cmd:")
        :cmd
      else
        :file
      end
    end
  end
end
