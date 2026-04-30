# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe KamalPullPreview::State do
  subject(:state) { described_class.new(db_path: db_path) }

  let(:db_path) { File.join(Dir.mktmpdir, "state.db") }

  after { FileUtils.rm_f(db_path) }

  describe "#upsert" do
    it "creates a new record" do
      state.upsert(pr_number: 1, sha: "abc1234", preview_url: "https://pr-1.example.com")
      record = state.find(1)
      expect(record).not_to be_nil
      expect(record["pr_number"]).to eq(1)
      expect(record["sha"]).to eq("abc1234")
      expect(record["preview_url"]).to eq("https://pr-1.example.com")
    end

    it "updates an existing record with the same pr_number" do
      state.upsert(pr_number: 1, sha: "abc1234", preview_url: "https://pr-1.example.com")
      state.upsert(pr_number: 1, sha: "def5678", preview_url: "https://pr-1-new.example.com")
      record = state.find(1)
      expect(record["sha"]).to eq("def5678")
      expect(record["preview_url"]).to eq("https://pr-1-new.example.com")
      expect(state.all.size).to eq(1)
    end
  end

  describe "#find" do
    it "returns nil for an unknown pr_number" do
      expect(state.find(9999)).to be_nil
    end
  end

  describe "#remove" do
    it "deletes the record" do
      state.upsert(pr_number: 2, sha: "abc1234", preview_url: "https://pr-2.example.com")
      state.remove(2)
      expect(state.find(2)).to be_nil
    end
  end

  describe "#expired" do
    it "returns previews older than ttl_hours" do
      state.upsert(pr_number: 3, sha: "abc1234", preview_url: "https://pr-3.example.com")

      # Manually set last_accessed_at to 3 days ago
      three_days_ago = (Time.now.utc - (3 * 24 * 3600)).iso8601
      db = SQLite3::Database.new(db_path)
      db.results_as_hash = true
      db.execute("UPDATE previews SET last_accessed_at = ? WHERE pr_number = 3", three_days_ago)
      db.close

      expired = state.expired(ttl_hours: 48)
      expect(expired.size).to eq(1)
      expect(expired.first["pr_number"]).to eq(3)
    end

    it "does not return previews within the ttl window" do
      state.upsert(pr_number: 4, sha: "abc1234", preview_url: "https://pr-4.example.com")
      expired = state.expired(ttl_hours: 48)
      expect(expired).to be_empty
    end
  end
end
