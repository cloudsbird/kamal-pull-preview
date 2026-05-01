# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe KamalPullPreview::Cleaner do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:db_path) { File.join(tmp_dir, "state.db") }
  let(:state)   { KamalPullPreview::State.new(db_path: db_path) }
  let(:deployer) { instance_double(KamalPullPreview::Deployer) }
  let(:cleaner)  { described_class.new(state: state, deployer: deployer) }

  after { FileUtils.rm_rf(tmp_dir) }

  describe "#list_previews" do
    it "returns an empty array when no previews exist" do
      expect(cleaner.list_previews).to eq([])
    end

    it "returns formatted rows for each preview" do
      state.upsert(pr_number: 1, sha: "abc1234", preview_url: "https://pr-1.example.com", status: "active")
      rows = cleaner.list_previews
      expect(rows.size).to eq(1)
      expect(rows.first[0]).to eq(1)          # PR
      expect(rows.first[1]).to eq("abc1234")  # SHA (first 7 chars)
      expect(rows.first[2]).to eq("https://pr-1.example.com") # URL
      expect(rows.first[3]).to eq("active")   # Status
      expect(rows.first[4]).to be_a(String)   # DeployedAt
    end

    it "truncates SHA to 7 characters" do
      state.upsert(pr_number: 2, sha: "abcd1234ef5678", preview_url: "https://pr-2.example.com")
      rows = cleaner.list_previews
      expect(rows.first[1]).to eq("abcd123")
    end

    it "orders previews by deployed_at descending" do
      state.upsert(pr_number: 1, sha: "a", preview_url: "https://pr-1.example.com")
      state.upsert(pr_number: 2, sha: "b", preview_url: "https://pr-2.example.com")

      db = SQLite3::Database.new(db_path)
      db.execute("UPDATE previews SET deployed_at = ? WHERE pr_number = 1", [(Time.now.utc - 3600).iso8601])
      db.close

      rows = cleaner.list_previews
      expect(rows.map(&:first)).to eq([2, 1])
    end
  end

  describe "#cleanup_expired" do
    before do
      allow(KamalPullPreview::Config).to receive(:load).and_return(
        KamalPullPreview::Config::ConfigStruct.new(
          host:              "deploy.example.com",
          domain:            "preview.example.com",
          ttl_hours:         48,
          idle_stop_minutes: 240,
          max_concurrent:    15,
          db_strategy:       "none",
          registry:          "registry.example.com/myorg/myapp",
        )
      )
    end

    it "returns 0 when no previews are expired" do
      state.upsert(pr_number: 1, sha: "a", preview_url: "https://pr-1.example.com")
      expect(deployer).not_to receive(:remove)
      expect(cleaner.cleanup_expired).to eq(0)
    end

    it "removes expired previews and returns the count" do
      state.upsert(pr_number: 1, sha: "a", preview_url: "https://pr-1.example.com")
      db = SQLite3::Database.new(db_path)
      db.execute(
        "UPDATE previews SET last_accessed_at = ? WHERE pr_number = 1",
        [(Time.now.utc - (100 * 3600)).iso8601]
      )
      db.close

      expect(deployer).to receive(:remove).with(pr_number: 1)
      expect(cleaner.cleanup_expired).to eq(1)
    end

    it "continues cleaning remaining previews when one removal fails" do
      state.upsert(pr_number: 1, sha: "a", preview_url: "https://pr-1.example.com")
      state.upsert(pr_number: 2, sha: "b", preview_url: "https://pr-2.example.com")

      db = SQLite3::Database.new(db_path)
      old_time = (Time.now.utc - (100 * 3600)).iso8601
      db.execute("UPDATE previews SET last_accessed_at = ? WHERE pr_number = 1", [old_time])
      db.execute("UPDATE previews SET last_accessed_at = ? WHERE pr_number = 2", [old_time])
      db.close

      expect(deployer).to receive(:remove).with(pr_number: 1)
        .and_raise(KamalPullPreview::DeployError, "kamal failed")
      expect(deployer).to receive(:remove).with(pr_number: 2)

      expect(cleaner.cleanup_expired).to eq(2)
    end

    it "accepts an explicit ttl_hours override" do
      state.upsert(pr_number: 1, sha: "a", preview_url: "https://pr-1.example.com")
      db = SQLite3::Database.new(db_path)
      db.execute(
        "UPDATE previews SET last_accessed_at = ? WHERE pr_number = 1",
        [(Time.now.utc - (25 * 3600)).iso8601]
      )
      db.close

      expect(deployer).to receive(:remove).with(pr_number: 1)
      expect(cleaner.cleanup_expired(ttl_hours: 24)).to eq(1)
    end
  end
end
