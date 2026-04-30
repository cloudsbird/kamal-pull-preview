# frozen_string_literal: true

require "open3"

module KamalPullPreview
  # Manages database lifecycle based on the configured db_strategy.
  # Currently supports per-PR PostgreSQL databases.
  class DatabaseManager
    def initialize(config: nil)
      @config = config || Config.load
    end

    # Create or ensure the database for the given PR exists.
    def setup(pr_number:)
      return unless @config.db_strategy == "postgresql"

      db_name = db_name_for(pr_number)
      logger.info("Ensuring PostgreSQL database exists: #{db_name}")

      if database_exists?(db_name)
        logger.info("PostgreSQL database already exists: #{db_name}")
      else
        psql("CREATE DATABASE #{db_name};", "postgres")
        logger.info("Created PostgreSQL database: #{db_name}")
      end
    end

    # Drop the database for the given PR.
    def teardown(pr_number:)
      return unless @config.db_strategy == "postgresql"

      db_name = db_name_for(pr_number)
      logger.info("Dropping PostgreSQL database: #{db_name}")
      psql("DROP DATABASE IF EXISTS #{db_name};", "postgres")
    end

    # Build a DATABASE_URL for the given PR.
    def database_url(pr_number:)
      return nil unless @config.db_strategy == "postgresql"

      db_name = db_name_for(pr_number)
      "postgresql://#{escape_userinfo(@config.pg_user)}:#{escape_userinfo(@config.pg_password)}@#{@config.pg_host}:#{@config.pg_port}/#{db_name}"
    end

    private

    def database_exists?(db_name)
      out = psql("SELECT 1 FROM pg_database WHERE datname = '#{db_name}';", "postgres")
      out.include?("(1 row)")
    end

    def psql(sql, db)
      env = { "PGPASSWORD" => @config.pg_password }
      cmd = ["psql", "-h", @config.pg_host, "-p", @config.pg_port.to_s, "-U", @config.pg_user, "-c", sql, db]
      out, status = Open3.capture2(env, *cmd)

      unless status.success?
        raise DbError, "PostgreSQL command failed: #{sql}\n#{out}"
      end

      out
    rescue Errno::ENOENT
      raise DbError, "psql command not found. Ensure PostgreSQL client is installed and on PATH."
    end

    def db_name_for(pr_number)
      "pr_#{Integer(pr_number)}"
    end

    def escape_userinfo(str)
      str.to_s.gsub(":", "%3A").gsub("@", "%40")
    end

    def logger
      KamalPullPreview.logger
    end
  end
end
