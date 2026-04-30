# frozen_string_literal: true

require "sqlite3"
require "fileutils"
require "time"

module KamalPullPreview
  # SQLite-backed persistence layer for preview environments.
  class State
    DB_DIR  = File.join(Dir.home, ".kamal-pull-preview")
    DB_PATH = File.join(DB_DIR, "state.db")

    def initialize(db_path: DB_PATH)
      FileUtils.mkdir_p(File.dirname(db_path))
      @db = SQLite3::Database.new(db_path)
      @db.results_as_hash = true
      migrate!
    end

    # Insert or update a preview record.
    def upsert(pr_number:, sha:, preview_url:, status: "active")
      now = Time.now.utc.iso8601
      @db.execute(<<~SQL, pr_number, sha, preview_url, now, now, status)
        INSERT INTO previews (pr_number, sha, preview_url, deployed_at, last_accessed_at, status)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(pr_number) DO UPDATE SET
          sha              = excluded.sha,
          preview_url      = excluded.preview_url,
          last_accessed_at = excluded.last_accessed_at,
          status           = excluded.status
      SQL
    end

    # Find a preview by PR number. Returns a Hash or nil.
    def find(pr_number)
      @db.get_first_row("SELECT * FROM previews WHERE pr_number = ?", pr_number)
    end

    # Return all preview records as an array of Hashes.
    def all
      @db.execute("SELECT * FROM previews ORDER BY deployed_at DESC")
    end

    # Delete a preview record by PR number.
    def remove(pr_number)
      @db.execute("DELETE FROM previews WHERE pr_number = ?", pr_number)
    end

    # Return previews whose last_accessed_at is older than ttl_hours.
    def expired(ttl_hours:)
      cutoff = (Time.now.utc - (ttl_hours * 3600)).iso8601
      @db.execute(
        "SELECT * FROM previews WHERE last_accessed_at < ? AND status = 'active'",
        cutoff,
      )
    end

    private

    def migrate!
      @db.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS previews (
          id               INTEGER PRIMARY KEY,
          pr_number        INTEGER UNIQUE NOT NULL,
          sha              TEXT,
          preview_url      TEXT,
          deployed_at      TEXT,
          last_accessed_at TEXT,
          status           TEXT DEFAULT 'active'
        )
      SQL
    end
  end
end
