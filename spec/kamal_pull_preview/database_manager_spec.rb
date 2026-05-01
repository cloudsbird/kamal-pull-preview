# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe KamalPullPreview::DatabaseManager do
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
      pg_user:           "preview_admin",
      pg_password:       "secret123",
    )
  end
  let(:none_config) do
    KamalPullPreview::Config::ConfigStruct.new(
      host:              "deploy.example.com",
      domain:            "preview.example.com",
      ttl_hours:         48,
      idle_stop_minutes: 240,
      max_concurrent:    15,
      db_strategy:       "none",
      registry:          "registry.example.com/myorg/myapp",
      pg_host:           "",
      pg_port:           0,
      pg_user:           "",
      pg_password:       "",
    )
  end

  describe "#setup" do
    context "with db_strategy 'none'" do
      let(:manager) { described_class.new(config: none_config) }

      it "is a no-op" do
        expect(manager).not_to receive(:psql)
        manager.setup(pr_number: 42)
      end
    end

    context "with db_strategy 'postgresql'" do
      let(:manager) { described_class.new(config: pg_config) }

      it "creates the database when it does not exist" do
        allow(manager).to receive(:database_exists?).with("pr_42").and_return(false)
        expect(manager).to receive(:psql).with("CREATE DATABASE pr_42;", "postgres")

        manager.setup(pr_number: 42)
      end

      it "skips creation when the database already exists" do
        allow(manager).to receive(:database_exists?).with("pr_42").and_return(true)
        expect(manager).not_to receive(:psql).with("CREATE DATABASE pr_42;", "postgres")

        manager.setup(pr_number: 42)
      end
    end
  end

  describe "#teardown" do
    context "with db_strategy 'none'" do
      let(:manager) { described_class.new(config: none_config) }

      it "is a no-op" do
        expect(manager).not_to receive(:psql)
        manager.teardown(pr_number: 42)
      end
    end

    context "with db_strategy 'postgresql'" do
      let(:manager) { described_class.new(config: pg_config) }

      it "drops the database" do
        expect(manager).to receive(:psql).with("DROP DATABASE IF EXISTS pr_42;", "postgres")
        manager.teardown(pr_number: 42)
      end
    end
  end

  describe "#database_url" do
    context "with db_strategy 'none'" do
      let(:manager) { described_class.new(config: none_config) }

      it "returns nil" do
        expect(manager.database_url(pr_number: 42)).to be_nil
      end
    end

    context "with db_strategy 'postgresql'" do
      let(:manager) { described_class.new(config: pg_config) }

      it "returns a PostgreSQL connection URL" do
        url = manager.database_url(pr_number: 42)
        expect(url).to eq("postgresql://preview_admin:secret123@db.example.com:5432/pr_42")
      end

      it "escapes special characters in credentials" do
        config_with_special = KamalPullPreview::Config::ConfigStruct.new(
          host:              "deploy.example.com",
          domain:            "preview.example.com",
          ttl_hours:         48,
          idle_stop_minutes: 240,
          max_concurrent:    15,
          db_strategy:       "postgresql",
          registry:          "registry.example.com/myorg/myapp",
          pg_host:           "db.example.com",
          pg_port:           5432,
          pg_user:           "user:name",
          pg_password:       "pass@word",
        )
        manager = described_class.new(config: config_with_special)
        url = manager.database_url(pr_number: 42)
        expect(url).to eq("postgresql://user%3Aname:pass%40word@db.example.com:5432/pr_42")
      end
    end
  end

  describe "#database_exists?" do
    let(:manager) { described_class.new(config: pg_config) }

    it "returns true when psql output contains a row" do
      allow(manager).to receive(:psql).and_return(" ?column? \n---------\n       1\n(1 row)\n")
      expect(manager.send(:database_exists?, "pr_42")).to be true
    end

    it "returns false when psql output contains no rows" do
      allow(manager).to receive(:psql).and_return(" ?column? \n---------\n(0 rows)\n")
      expect(manager.send(:database_exists?, "pr_42")).to be false
    end
  end

  describe "#restore_seed" do
    let(:seed_config) do
      KamalPullPreview::Config::ConfigStruct.new(
        host:              "deploy.example.com",
        domain:            "preview.example.com",
        ttl_hours:         48,
        idle_stop_minutes: 240,
        max_concurrent:    15,
        db_strategy:       "none",
        registry:          "registry.example.com/myorg/myapp",
        pg_host:           "",
        pg_port:           0,
        pg_user:           "",
        pg_password:       "",
        db_seed: {
          "source"      => "s3://bucket/dump.sql",
          "format"      => "auto",
          "required"    => false,
          "table_check" => false,
        },
      )
    end

    context "when db_seed is not configured" do
      let(:manager) { described_class.new(config: none_config) }

      it "is a no-op" do
        expect(KamalPullPreview::DumpFetcher).not_to receive(:new)
        manager.restore_seed(pr_number: 42, destination_type: :none)
      end
    end

    context "when source is unreachable and required: false" do
      let(:manager) { described_class.new(config: seed_config) }

      it "logs a warning and returns without raising" do
        allow_any_instance_of(KamalPullPreview::DumpFetcher).to receive(:available?).and_return(false)
        expect { manager.restore_seed(pr_number: 42, destination_type: :none) }.not_to raise_error
      end
    end

    context "when source is unreachable and required: true" do
      let(:required_seed_config) do
        KamalPullPreview::Config::ConfigStruct.new(
          host:              "deploy.example.com",
          domain:            "preview.example.com",
          ttl_hours:         48,
          idle_stop_minutes: 240,
          max_concurrent:    15,
          db_strategy:       "none",
          registry:          "registry.example.com/myorg/myapp",
          pg_host:           "",
          pg_port:           0,
          pg_user:           "",
          pg_password:       "",
          db_seed: {
            "source"      => "s3://bucket/dump.sql",
            "format"      => "auto",
            "required"    => true,
            "table_check" => false,
          },
        )
      end
      let(:manager) { described_class.new(config: required_seed_config) }

      it "raises DbError" do
        allow_any_instance_of(KamalPullPreview::DumpFetcher).to receive(:available?).and_return(false)
        expect {
          manager.restore_seed(pr_number: 42, destination_type: :none)
        }.to raise_error(KamalPullPreview::DbError, /required but unreachable/)
      end
    end

    context "when table_check is true and tables already exist" do
      let(:table_check_config) do
        KamalPullPreview::Config::ConfigStruct.new(
          host:              "deploy.example.com",
          domain:            "preview.example.com",
          ttl_hours:         48,
          idle_stop_minutes: 240,
          max_concurrent:    15,
          db_strategy:       "none",
          registry:          "registry.example.com/myorg/myapp",
          pg_host:           "",
          pg_port:           0,
          pg_user:           "",
          pg_password:       "",
          db_seed: {
            "source"      => "s3://bucket/dump.sql",
            "format"      => "auto",
            "required"    => false,
            "table_check" => true,
          },
        )
      end
      let(:manager) { described_class.new(config: table_check_config) }

      it "skips the restore" do
        allow_any_instance_of(KamalPullPreview::DumpFetcher).to receive(:available?).and_return(true)
        allow(manager).to receive(:tables_exist?).and_return(true)
        expect_any_instance_of(KamalPullPreview::DumpFetcher).not_to receive(:fetch)
        manager.restore_seed(pr_number: 42, destination_type: :shared_schema)
      end
    end

    context "when source is available and table_check is false" do
      let(:manager) { described_class.new(config: seed_config) }

      it "fetches the dump and calls restore for :none destination_type" do
        allow_any_instance_of(KamalPullPreview::DumpFetcher).to receive(:available?).and_return(true)
        allow_any_instance_of(KamalPullPreview::DumpFetcher).to receive(:fetch).and_return("/tmp/dump.sql")
        allow_any_instance_of(KamalPullPreview::DumpFetcher).to receive(:detect_format).and_return("plain")
        expect { manager.restore_seed(pr_number: 42, destination_type: :none) }.not_to raise_error
      end
    end
  end
end
