# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe KamalPullPreview::Deployer do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:config) do
    KamalPullPreview::Config::ConfigStruct.new(
      host:              "deploy.example.com",
      domain:            "preview.example.com",
      ttl_hours:         48,
      idle_stop_minutes: 240,
      max_concurrent:    2,
      db_strategy:       "none",
      registry:          "registry.example.com/myorg/myapp",
    )
  end
  let(:state)       { instance_double(KamalPullPreview::State) }
  let(:generator)   { instance_double(KamalPullPreview::DestinationGenerator) }
  let(:db_manager)  { instance_double(KamalPullPreview::DatabaseManager) }
  let(:deployer)    { described_class.new(config: config, state: state, generator: generator, db_manager: db_manager) }

  around do |example|
    Dir.chdir(tmp_dir) { example.run }
  end

  after { FileUtils.rm_rf(tmp_dir) }

  before do
    allow(KamalPullPreview::Executor).to receive(:execute)
    allow(generator).to receive(:generate).and_return(".kamal/destinations/pr-42.yml")
    allow(generator).to receive(:cleanup)
    allow(state).to receive(:upsert)
    allow(state).to receive(:remove)
    allow(state).to receive(:all).and_return([])
    allow(db_manager).to receive(:setup)
    allow(db_manager).to receive(:teardown)
  end

  describe "#deploy" do
    it "checks capacity, generates destination, runs kamal deploy, and records state" do
      expect(db_manager).to receive(:setup).with(pr_number: 42)
      expect(generator).to receive(:generate).with(pr_number: 42).and_return(".kamal/destinations/pr-42.yml")
      expect(KamalPullPreview::Executor).to receive(:execute).with("kamal", "deploy", "-d", "pr-42")
      expect(state).to receive(:upsert).with(pr_number: 42, sha: "abc1234", preview_url: "https://pr-42.preview.example.com")

      url = deployer.deploy(pr_number: 42, sha: "abc1234")
      expect(url).to eq("https://pr-42.preview.example.com")
    end

    it "raises DeployError when max concurrent is reached" do
      allow(state).to receive(:all).and_return([
        { "status" => "active" },
        { "status" => "active" },
      ])

      expect {
        deployer.deploy(pr_number: 42, sha: "abc1234")
      }.to raise_error(KamalPullPreview::DeployError, /Maximum concurrent previews reached/)
    end

    it "passes repo to logger but does not require it for functionality" do
      expect(KamalPullPreview::Executor).to receive(:execute)
      expect(state).to receive(:upsert)

      deployer.deploy(pr_number: 42, sha: "abc1234", repo: "owner/repo")
    end

    it "raises DeployError for non-numeric PR number" do
      expect {
        deployer.deploy(pr_number: "abc", sha: "abc1234")
      }.to raise_error(KamalPullPreview::DeployError, /PR number must be a positive integer/)
    end

    it "raises DeployError for negative PR number" do
      expect {
        deployer.deploy(pr_number: -1, sha: "abc1234")
      }.to raise_error(KamalPullPreview::DeployError, /PR number must be a positive integer/)
    end

    it "raises DeployError for zero PR number" do
      expect {
        deployer.deploy(pr_number: 0, sha: "abc1234")
      }.to raise_error(KamalPullPreview::DeployError, /PR number must be a positive integer/)
    end
  end

  describe "#remove" do
    before do
      FileUtils.mkdir_p(".kamal/destinations")
      File.write(".kamal/destinations/pr-42.yml", "dummy")
    end

    it "runs kamal remove, cleans up destination, drops database, and deletes state" do
      expect(KamalPullPreview::Executor).to receive(:execute).with("kamal", "remove", "-d", "pr-42")
      expect(generator).to receive(:cleanup).with(pr_number: 42)
      expect(db_manager).to receive(:teardown).with(pr_number: 42)
      expect(state).to receive(:remove).with(42)

      deployer.remove(pr_number: 42)
    end

    it "cleans up database and state even when destination file is missing" do
      FileUtils.rm(".kamal/destinations/pr-42.yml")
      expect(KamalPullPreview::Executor).not_to receive(:execute)
      expect(db_manager).to receive(:teardown).with(pr_number: 42)
      expect(state).to receive(:remove).with(42)

      deployer.remove(pr_number: 42)
    end

    it "cleans up database and state even when kamal remove fails" do
      expect(KamalPullPreview::Executor).to receive(:execute).and_raise(KamalPullPreview::DeployError, "kamal failed")
      expect(db_manager).to receive(:teardown).with(pr_number: 42)
      expect(state).to receive(:remove).with(42)

      expect {
        deployer.remove(pr_number: 42)
      }.to raise_error(KamalPullPreview::DeployError, /kamal failed/)
    end

    it "raises DeployError for non-numeric PR number" do
      expect {
        deployer.remove(pr_number: "abc")
      }.to raise_error(KamalPullPreview::DeployError, /PR number must be a positive integer/)
    end

    it "raises DeployError for negative PR number" do
      expect {
        deployer.remove(pr_number: -5)
      }.to raise_error(KamalPullPreview::DeployError, /PR number must be a positive integer/)
    end
  end
end
