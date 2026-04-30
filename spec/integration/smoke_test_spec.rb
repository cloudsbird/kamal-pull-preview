# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "tempfile"

RSpec.describe "Integration smoke test" do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:db_path) { File.join(tmp_dir, "state.db") }

  around do |example|
    Dir.chdir(tmp_dir) { example.run }
  end

  after { FileUtils.rm_rf(tmp_dir) }

  def write_config
    File.write("kamal-pull-preview.yml", <<~YAML)
      host: "deploy.example.com"
      domain: "preview.example.com"
      registry: "registry.example.com/myorg/myapp"
      ttl_hours: 48
      max_concurrent: 5
    YAML
  end

  before do
    write_config
    allow(KamalPullPreview::Executor).to receive(:execute)
  end

  it "deploys a preview, lists it, and removes it" do
    state    = KamalPullPreview::State.new(db_path: db_path)
    deployer = KamalPullPreview::Deployer.new(state: state)

    # Deploy
    url = deployer.deploy(pr_number: 99, sha: "deadbeef")
    expect(url).to eq("https://pr-99.preview.example.com")

    # List
    cleaner = KamalPullPreview::Cleaner.new(state: state)
    rows = cleaner.list_previews
    expect(rows.size).to eq(1)
    expect(rows.first[0]).to eq(99)
    expect(rows.first[2]).to eq("https://pr-99.preview.example.com")

    # Remove
    deployer.remove(pr_number: 99)
    rows = cleaner.list_previews
    expect(rows).to be_empty
  end

  it "respects TTL expiry in cleanup" do
    state    = KamalPullPreview::State.new(db_path: db_path)
    deployer = KamalPullPreview::Deployer.new(state: state)

    deployer.deploy(pr_number: 1, sha: "abc1234")

    # Manually age the record
    db = SQLite3::Database.new(db_path)
    db.execute("UPDATE previews SET last_accessed_at = ? WHERE pr_number = 1", [(Time.now.utc - (100 * 3600)).iso8601])
    db.close

    cleaner = KamalPullPreview::Cleaner.new(state: state)
    removed = cleaner.cleanup_expired(ttl_hours: 48)
    expect(removed).to eq(1)
    expect(state.find(1)).to be_nil
  end
end
