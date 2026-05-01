# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe KamalPullPreview::DeployConfigReader do
  let(:tmp_dir) { Dir.mktmpdir }

  around do |example|
    Dir.chdir(tmp_dir) { example.run }
  end

  after { FileUtils.rm_rf(tmp_dir) }

  context "when deploy.yml is missing" do
    it "returns empty accessories" do
      reader = described_class.new(path: "config/deploy.yml")
      expect(reader.accessories).to eq({})
    end

    it "returns ['web'] for server_roles" do
      reader = described_class.new(path: "config/deploy.yml")
      expect(reader.server_roles).to eq(["web"])
    end
  end

  context "when deploy.yml has accessories and servers" do
    before do
      FileUtils.mkdir_p(File.join(tmp_dir, "config"))
      File.write(
        File.join(tmp_dir, "config", "deploy.yml"),
        <<~YAML
          servers:
            web:
              - 1.2.3.4
            sidekiq:
              hosts:
                - 1.2.3.4

          accessories:
            redis:
              image: redis:7
              port: 6379
            postgres:
              image: postgres:15
              port: 5432
        YAML
      )
    end

    it "returns accessories hash" do
      reader = described_class.new(path: "config/deploy.yml")
      expect(reader.accessories.keys).to contain_exactly("redis", "postgres")
    end

    it "returns server roles" do
      reader = described_class.new(path: "config/deploy.yml")
      expect(reader.server_roles).to contain_exactly("web", "sidekiq")
    end
  end

  context "when deploy.yml has no accessories key" do
    before do
      FileUtils.mkdir_p(File.join(tmp_dir, "config"))
      File.write(
        File.join(tmp_dir, "config", "deploy.yml"),
        <<~YAML
          servers:
            web:
              - 1.2.3.4
        YAML
      )
    end

    it "returns empty accessories" do
      reader = described_class.new(path: "config/deploy.yml")
      expect(reader.accessories).to eq({})
    end
  end

  context "when deploy.yml has a YAML syntax error" do
    before do
      FileUtils.mkdir_p(File.join(tmp_dir, "config"))
      File.write(File.join(tmp_dir, "config", "deploy.yml"), ":::: broken yaml ::::")
    end

    it "returns empty accessories" do
      reader = described_class.new(path: "config/deploy.yml")
      expect(reader.accessories).to eq({})
    end

    it "returns ['web'] for server_roles" do
      reader = described_class.new(path: "config/deploy.yml")
      expect(reader.server_roles).to eq(["web"])
    end
  end
end
