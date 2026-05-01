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

    # Restore a database seed dump if db_seed is configured.
    # destination_type: :shared_schema | :accessory_postgres | :sqlite | :none
    def restore_seed(pr_number:, destination_type:)
      return unless @config.respond_to?(:db_seed) && @config.db_seed

      seed_cfg     = @config.db_seed
      source       = seed_cfg["source"].to_s
      format       = seed_cfg["format"] || "auto"
      required     = seed_cfg["required"]
      table_check  = seed_cfg.key?("table_check") ? seed_cfg["table_check"] : true

      fetcher = DumpFetcher.new(source: source, format: format)

      unless fetcher.available?
        if required
          raise DbError, "Seed source is required but unreachable: #{source}"
        else
          logger.warn("Seed source unreachable, skipping: #{source}")
          return
        end
      end

      if table_check && tables_exist?(pr_number: pr_number, destination_type: destination_type)
        logger.info("Tables already exist for PR ##{pr_number}, skipping seed restore")
        return
      end

      dump_path        = fetcher.fetch
      effective_format = format == "auto" ? fetcher.detect_format : format

      case destination_type
      when :shared_schema
        restore_to_shared_schema(pr_number: pr_number, dump_path: dump_path, format: effective_format)
      when :accessory_postgres
        restore_to_accessory_postgres(pr_number: pr_number, dump_path: dump_path, format: effective_format)
      when :sqlite
        restore_to_sqlite(pr_number: pr_number, dump_path: dump_path)
      when :none
        logger.warn("destination_type is :none, skipping seed restore for PR ##{pr_number}")
      else
        logger.warn("Unknown destination_type '#{destination_type}', skipping seed restore for PR ##{pr_number}")
      end
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

    def tables_exist?(pr_number:, destination_type:)
      case destination_type
      when :shared_schema
        # pr_number is coerced to Integer, making the schema name injection-safe.
        schema = "pr_#{Integer(pr_number)}"
        out = psql(
          "SELECT count(*) FROM information_schema.tables WHERE table_schema = '#{schema}';",
          db_name_for(pr_number)
        )
        out.match?(/^\s*[1-9]/)
      when :sqlite
        # SQLite volumes are not locally accessible; skip table check.
        false
      else
        false
      end
    rescue DbError
      false
    end

    def restore_to_shared_schema(pr_number:, dump_path:, format:)
      schema = "pr_#{Integer(pr_number)}"
      db     = db_name_for(pr_number)
      if format == "custom"
        env = { "PGPASSWORD" => @config.pg_password }
        cmd = [
          "pg_restore", "-h", @config.pg_host, "-p", @config.pg_port.to_s,
          "-U", @config.pg_user, "-d", db,
          "--schema=#{schema}", "--no-owner", "--no-acl", dump_path,
        ]
        _, status = Open3.capture2(env, *cmd)
        raise DbError, "pg_restore failed for PR ##{pr_number}" unless status.success?
      else
        # Pass the dump file as a psql --file argument to avoid shell injection.
        env = { "PGPASSWORD" => @config.pg_password }
        cmd = [
          "psql", "-h", @config.pg_host, "-p", @config.pg_port.to_s,
          "-U", @config.pg_user, "--file", dump_path, db,
        ]
        _, status = Open3.capture2(env, *cmd)
        raise DbError, "psql restore failed for PR ##{pr_number}" unless status.success?
      end
    end

    def restore_to_accessory_postgres(pr_number:, dump_path:, format:)
      logger.info("Accessory postgres seed restore is not yet automated for PR ##{pr_number} (format: #{format})")
    end

    def restore_to_sqlite(pr_number:, dump_path:)
      logger.info("SQLite seed restore is not yet automated for PR ##{pr_number} (path: #{dump_path})")
    end

    def logger
      KamalPullPreview.logger
    end
  end
end
