# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "tempfile"

RSpec.describe KamalPullPreview::DestinationGenerator do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:config) do
    KamalPullPreview::Config::ConfigStruct.new(
      host:              "deploy.example.com",
      domain:            "preview.example.com",
      ttl_hours:         48,
      idle_stop_minutes: 240,
      max_concurrent:    15,
      db_strategy:       "none",
      registry:          "registry.example.com/myorg/myapp",
    )
  end
  let(:generator) { described_class.new(config: config) }
  let(:expected_path) { File.join(tmp_dir, ".kamal", "destinations", "pr-42.yml") }

  around do |example|
    Dir.chdir(tmp_dir) { example.run }
  end

  after { FileUtils.rm_rf(tmp_dir) }

  describe "#generate" do
    it "writes a valid YAML file at .kamal/destinations/pr-{n}.yml" do
      path = generator.generate(pr_number: 42)
      expect(File.exist?(path)).to be true
      expect(path).to end_with("pr-42.yml")
    end

    it "generates a file with correct proxy host" do
      generator.generate(pr_number: 42)
      content = YAML.safe_load(File.read(expected_path))
      expect(content["proxy"]["host"]).to eq("pr-42.preview.example.com")
    end

    context "with postgresql db_strategy" do
      let(:pg_config) do
        KamalPullPreview::Config::ConfigStruct.new(
          host:              "deploy.example.com",
          domain:            "preview.example.com",
          ttl_hours:         48,
          idle_stop_minutes: 240,
          max_concurrent:    15,
          db_strategy:       "postgresql",
          registry:          "registry.example.com/myorg/myapp",
          pg_host:           "db.example.com",
          pg_port:           5432,
          pg_user:           "admin",
          pg_password:       "secret",
        )
      end
      let(:generator) { described_class.new(config: pg_config) }

      it "includes DATABASE_URL in the destination env" do
        generator.generate(pr_number: 42)
        content = YAML.safe_load(File.read(expected_path))
        expect(content["env"]["clear"]["DATABASE_URL"])
          .to eq("postgresql://admin:secret@db.example.com:5432/pr_42")
      end
    end
  end

  describe "#cleanup" do
    it "removes the generated file" do
      generator.generate(pr_number: 42)
      expect(File.exist?(expected_path)).to be true
      generator.cleanup(pr_number: 42)
      expect(File.exist?(expected_path)).to be false
    end
  end
end
