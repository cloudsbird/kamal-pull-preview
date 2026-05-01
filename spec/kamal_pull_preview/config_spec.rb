# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe KamalPullPreview::Config do
  def write_config(content)
    file = Tempfile.new(["kamal-pull-preview", ".yml"])
    file.write(content)
    file.flush
    file
  end

  describe ".load" do
    context "when host is missing" do
      it "raises ConfigError" do
        file = write_config(<<~YAML)
          domain: "preview.example.com"
          registry: "registry.example.com/myorg/myapp"
        YAML
        expect { described_class.load(path: file.path) }
          .to raise_error(KamalPullPreview::ConfigError, /host/)
        file.close
      end
    end

    context "when domain is missing" do
      it "raises ConfigError" do
        file = write_config(<<~YAML)
          host: "preview.example.com"
          registry: "registry.example.com/myorg/myapp"
        YAML
        expect { described_class.load(path: file.path) }
          .to raise_error(KamalPullPreview::ConfigError, /domain/)
        file.close
      end
    end

    context "with defaults" do
      it "returns default ttl_hours of 48" do
        file = write_config(<<~YAML)
          host: "preview.example.com"
          domain: "preview.example.com"
          registry: "registry.example.com/myorg/myapp"
        YAML
        config = described_class.load(path: file.path)
        expect(config.ttl_hours).to eq(48)
        file.close
      end

      it "returns default max_concurrent of 15" do
        file = write_config(<<~YAML)
          host: "preview.example.com"
          domain: "preview.example.com"
          registry: "registry.example.com/myorg/myapp"
        YAML
        config = described_class.load(path: file.path)
        expect(config.max_concurrent).to eq(15)
        file.close
      end

      it "returns default db_strategy of 'none'" do
        file = write_config(<<~YAML)
          host: "preview.example.com"
          domain: "preview.example.com"
          registry: "registry.example.com/myorg/myapp"
        YAML
        config = described_class.load(path: file.path)
        expect(config.db_strategy).to eq("none")
        file.close
      end
    end

    context "with a valid config file" do
      it "loads all fields correctly" do
        file = write_config(<<~YAML)
          host: "deploy.example.com"
          domain: "preview.example.com"
          registry: "registry.example.com/myorg/myapp"
          ttl_hours: 72
          max_concurrent: 5
          db_strategy: "sqlite"
        YAML
        config = described_class.load(path: file.path)
        expect(config.host).to eq("deploy.example.com")
        expect(config.domain).to eq("preview.example.com")
        expect(config.registry).to eq("registry.example.com/myorg/myapp")
        expect(config.ttl_hours).to eq(72)
        expect(config.max_concurrent).to eq(5)
        expect(config.db_strategy).to eq("sqlite")
        file.close
      end
    end

    context "with postgresql strategy" do
      it "accepts postgresql as a valid db_strategy" do
        file = write_config(<<~YAML)
          host: "deploy.example.com"
          domain: "preview.example.com"
          registry: "registry.example.com/myorg/myapp"
          db_strategy: "postgresql"
          pg_host: "db.example.com"
          pg_user: "admin"
          pg_password: "secret"
        YAML
        config = described_class.load(path: file.path)
        expect(config.db_strategy).to eq("postgresql")
        expect(config.pg_host).to eq("db.example.com")
        expect(config.pg_port).to eq(5432)
        expect(config.pg_user).to eq("admin")
        expect(config.pg_password).to eq("secret")
        file.close
      end

      it "raises ConfigError when pg_host is missing" do
        file = write_config(<<~YAML)
          host: "deploy.example.com"
          domain: "preview.example.com"
          registry: "registry.example.com/myorg/myapp"
          db_strategy: "postgresql"
          pg_user: "admin"
          pg_password: "secret"
        YAML
        expect { described_class.load(path: file.path) }
          .to raise_error(KamalPullPreview::ConfigError, /pg_host/)
        file.close
      end

      it "raises ConfigError when pg_user is missing" do
        file = write_config(<<~YAML)
          host: "deploy.example.com"
          domain: "preview.example.com"
          registry: "registry.example.com/myorg/myapp"
          db_strategy: "postgresql"
          pg_host: "db.example.com"
          pg_password: "secret"
        YAML
        expect { described_class.load(path: file.path) }
          .to raise_error(KamalPullPreview::ConfigError, /pg_user/)
        file.close
      end

      it "raises ConfigError when pg_password is missing" do
        file = write_config(<<~YAML)
          host: "deploy.example.com"
          domain: "preview.example.com"
          registry: "registry.example.com/myorg/myapp"
          db_strategy: "postgresql"
          pg_host: "db.example.com"
          pg_user: "admin"
        YAML
        expect { described_class.load(path: file.path) }
          .to raise_error(KamalPullPreview::ConfigError, /pg_password/)
        file.close
      end
    end

    context "with db_seed" do
      it "loads db_seed with defaults when only source is provided" do
        file = write_config(<<~YAML)
          host: "deploy.example.com"
          domain: "preview.example.com"
          registry: "registry.example.com/myorg/myapp"
          db_seed:
            source: "s3://my-bucket/dumps/latest.dump"
        YAML
        config = described_class.load(path: file.path)
        expect(config.db_seed["source"]).to eq("s3://my-bucket/dumps/latest.dump")
        expect(config.db_seed["format"]).to eq("auto")
        expect(config.db_seed["required"]).to be false
        expect(config.db_seed["table_check"]).to be true
        file.close
      end

      it "loads db_seed with all fields specified" do
        file = write_config(<<~YAML)
          host: "deploy.example.com"
          domain: "preview.example.com"
          registry: "registry.example.com/myorg/myapp"
          db_seed:
            source: "https://example.com/dump.dump"
            format: custom
            required: true
            table_check: false
        YAML
        config = described_class.load(path: file.path)
        expect(config.db_seed["source"]).to eq("https://example.com/dump.dump")
        expect(config.db_seed["format"]).to eq("custom")
        expect(config.db_seed["required"]).to be true
        expect(config.db_seed["table_check"]).to be false
        file.close
      end

      it "raises ConfigError when db_seed source is missing" do
        file = write_config(<<~YAML)
          host: "deploy.example.com"
          domain: "preview.example.com"
          registry: "registry.example.com/myorg/myapp"
          db_seed:
            format: custom
        YAML
        expect { described_class.load(path: file.path) }
          .to raise_error(KamalPullPreview::ConfigError, /source/)
        file.close
      end

      it "raises ConfigError when db_seed format is invalid" do
        file = write_config(<<~YAML)
          host: "deploy.example.com"
          domain: "preview.example.com"
          registry: "registry.example.com/myorg/myapp"
          db_seed:
            source: "s3://bucket/dump.sql"
            format: invalid_format
        YAML
        expect { described_class.load(path: file.path) }
          .to raise_error(KamalPullPreview::ConfigError, /format/)
        file.close
      end

      it "returns nil db_seed when not configured" do
        file = write_config(<<~YAML)
          host: "deploy.example.com"
          domain: "preview.example.com"
          registry: "registry.example.com/myorg/myapp"
        YAML
        config = described_class.load(path: file.path)
        expect(config.db_seed).to be_nil
        file.close
      end
    end
  end
end
