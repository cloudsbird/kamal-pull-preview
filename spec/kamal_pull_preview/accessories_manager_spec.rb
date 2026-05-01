# frozen_string_literal: true

require "spec_helper"

RSpec.describe KamalPullPreview::AccessoriesManager do
  let(:host) { "preview.example.com" }
  let(:pr_number) { 42 }
  let(:redis_config) { { "image" => "redis:7", "port" => "6379" } }
  let(:pg_config)    { { "image" => "postgres:15", "port" => "5432" } }
  let(:mysql_config) { { "image" => "mysql:8", "port" => "3306" } }

  subject(:manager) do
    described_class.new(
      accessories_config:  { "redis" => redis_config },
      pr_number:           pr_number,
      host:                host,
      accessories_setting: :auto,
    )
  end

  describe "#scoped_accessories" do
    it "returns empty hash when accessories_setting is :none" do
      mgr = described_class.new(
        accessories_config:  { "redis" => redis_config },
        pr_number:           pr_number,
        host:                host,
        accessories_setting: :none,
      )
      expect(mgr.scoped_accessories).to eq({})
    end

    it "prefixes name with pr-{N}-" do
      expect(manager.scoped_accessories.keys).to eq(["pr-42-redis"])
    end

    it "sets host to the provided host" do
      expect(manager.scoped_accessories["pr-42-redis"]["host"]).to eq(host)
    end

    it "computes port using pr_port formula" do
      # 6379 + 10000 + (42 % 1000) = 16421
      expect(manager.scoped_accessories["pr-42-redis"]["port"]).to eq("16421")
    end

    it "filters to allowlist when accessories_setting is an array" do
      mgr = described_class.new(
        accessories_config:  { "redis" => redis_config, "postgres" => pg_config },
        pr_number:           pr_number,
        host:                host,
        accessories_setting: ["redis"],
      )
      expect(mgr.scoped_accessories.keys).to eq(["pr-42-redis"])
    end

    it "returns empty hash when no accessories_config" do
      mgr = described_class.new(
        accessories_config:  {},
        pr_number:           pr_number,
        host:                host,
        accessories_setting: :auto,
      )
      expect(mgr.scoped_accessories).to eq({})
    end
  end

  describe "#env_overrides" do
    it "returns REDIS_URL for redis accessory" do
      expect(manager.env_overrides["REDIS_URL"]).to eq("redis://preview.example.com:16421/0")
    end

    it "returns DATABASE_URL for postgres accessory" do
      mgr = described_class.new(
        accessories_config:  { "postgres" => pg_config },
        pr_number:           pr_number,
        host:                host,
        accessories_setting: :auto,
      )
      # 5432 + 10000 + 42 = 15474
      expect(mgr.env_overrides["DATABASE_URL"]).to eq("postgres://postgres@preview.example.com:15474/preview")
    end

    it "returns DATABASE_URL for pg-named accessory" do
      mgr = described_class.new(
        accessories_config:  { "pg" => pg_config },
        pr_number:           pr_number,
        host:                host,
        accessories_setting: :auto,
      )
      expect(mgr.env_overrides["DATABASE_URL"]).to start_with("postgres://")
    end

    it "returns DATABASE_URL for mysql accessory" do
      mgr = described_class.new(
        accessories_config:  { "mysql" => mysql_config },
        pr_number:           pr_number,
        host:                host,
        accessories_setting: :auto,
      )
      # 3306 + 10000 + 42 = 13348
      expect(mgr.env_overrides["DATABASE_URL"]).to eq("mysql2://root@preview.example.com:13348/preview")
    end

    it "returns empty hash when accessories_setting is :none" do
      mgr = described_class.new(
        accessories_config:  { "redis" => redis_config },
        pr_number:           pr_number,
        host:                host,
        accessories_setting: :none,
      )
      expect(mgr.env_overrides).to eq({})
    end

    it "returns empty hash when no accessories_config" do
      mgr = described_class.new(
        accessories_config:  {},
        pr_number:           pr_number,
        host:                host,
        accessories_setting: :auto,
      )
      expect(mgr.env_overrides).to eq({})
    end
  end

  describe "#boot_all" do
    it "calls kamal accessory boot for each scoped accessory" do
      expect(KamalPullPreview::Executor).to receive(:execute)
        .with("kamal", "accessory", "boot", "pr-42-redis", "-d", "pr-42")
      manager.boot_all
    end

    it "does nothing when accessories_setting is :none" do
      mgr = described_class.new(
        accessories_config:  { "redis" => redis_config },
        pr_number:           pr_number,
        host:                host,
        accessories_setting: :none,
      )
      expect(KamalPullPreview::Executor).not_to receive(:execute)
      mgr.boot_all
    end
  end

  describe "#remove_all" do
    it "calls kamal accessory remove for each scoped accessory" do
      expect(KamalPullPreview::Executor).to receive(:execute)
        .with("kamal", "accessory", "remove", "pr-42-redis", "-d", "pr-42")
      manager.remove_all
    end

    it "does nothing when accessories_setting is :none" do
      mgr = described_class.new(
        accessories_config:  { "redis" => redis_config },
        pr_number:           pr_number,
        host:                host,
        accessories_setting: :none,
      )
      expect(KamalPullPreview::Executor).not_to receive(:execute)
      mgr.remove_all
    end
  end
end
