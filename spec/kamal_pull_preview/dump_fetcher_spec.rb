# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "tempfile"

RSpec.describe KamalPullPreview::DumpFetcher do
  describe "#available?" do
    context "with s3:// source" do
      subject(:fetcher) { described_class.new(source: "s3://my-bucket/dumps/latest.dump") }

      it "returns true when aws s3 ls succeeds" do
        allow(Open3).to receive(:capture2e)
          .with("aws", "s3", "ls", "s3://my-bucket/dumps/latest.dump")
          .and_return(["", double(success?: true)])
        expect(fetcher.available?).to be true
      end

      it "returns false when aws s3 ls fails" do
        allow(Open3).to receive(:capture2e)
          .with("aws", "s3", "ls", "s3://my-bucket/dumps/latest.dump")
          .and_return(["", double(success?: false)])
        expect(fetcher.available?).to be false
      end
    end

    context "with https:// source" do
      subject(:fetcher) { described_class.new(source: "https://example.com/dump.sql") }

      it "returns true when curl HEAD succeeds" do
        allow(Open3).to receive(:capture2e)
          .with("curl", "-fsI", "--max-time", "10", "https://example.com/dump.sql")
          .and_return(["HTTP/2 200", double(success?: true)])
        expect(fetcher.available?).to be true
      end

      it "returns false when curl HEAD fails" do
        allow(Open3).to receive(:capture2e)
          .with("curl", "-fsI", "--max-time", "10", "https://example.com/dump.sql")
          .and_return(["", double(success?: false)])
        expect(fetcher.available?).to be false
      end
    end

    context "with http:// source" do
      subject(:fetcher) { described_class.new(source: "http://internal.example.com/dump.sql") }

      it "returns true when curl HEAD succeeds" do
        allow(Open3).to receive(:capture2e)
          .with("curl", "-fsI", "--max-time", "10", "http://internal.example.com/dump.sql")
          .and_return(["HTTP/1.1 200", double(success?: true)])
        expect(fetcher.available?).to be true
      end
    end

    context "with bare file path source" do
      subject(:fetcher) { described_class.new(source: "/var/backups/dump.sql") }

      it "returns true when file exists" do
        allow(File).to receive(:exist?).with("/var/backups/dump.sql").and_return(true)
        expect(fetcher.available?).to be true
      end

      it "returns false when file does not exist" do
        allow(File).to receive(:exist?).with("/var/backups/dump.sql").and_return(false)
        expect(fetcher.available?).to be false
      end
    end

    context "with cmd: source" do
      subject(:fetcher) { described_class.new(source: "cmd:pg_dump mydb") }

      it "always returns true" do
        expect(fetcher.available?).to be true
      end
    end
  end

  describe "#fetch" do
    context "with bare file path source" do
      subject(:fetcher) { described_class.new(source: "/var/backups/dump.sql") }

      it "returns the original path without copying" do
        expect(fetcher.fetch).to eq("/var/backups/dump.sql")
      end
    end

    context "with s3:// source" do
      subject(:fetcher) { described_class.new(source: "s3://bucket/dump.sql") }

      it "executes aws s3 cp and returns a temp file path" do
        expect(KamalPullPreview::Executor).to receive(:execute)
          .with("aws", "s3", "cp", "s3://bucket/dump.sql", anything)
        path = fetcher.fetch
        expect(path).to be_a(String)
        expect(path).not_to be_empty
      end
    end

    context "with https:// source" do
      subject(:fetcher) { described_class.new(source: "https://example.com/dump.sql") }

      it "executes curl and returns a temp file path" do
        expect(KamalPullPreview::Executor).to receive(:execute)
          .with("curl", "-fsSL", "-o", anything, "https://example.com/dump.sql")
        path = fetcher.fetch
        expect(path).to be_a(String)
      end
    end

    context "with cmd: source" do
      subject(:fetcher) { described_class.new(source: "cmd:echo hello") }

      it "executes the command and writes output to a temp file" do
        allow(Open3).to receive(:capture2)
          .with("echo hello")
          .and_return(["hello\n", double(success?: true)])
        path = fetcher.fetch
        expect(path).to be_a(String)
      end

      it "raises DbError when the command fails" do
        allow(Open3).to receive(:capture2)
          .with("pg_dump --fail")
          .and_return(["", double(success?: false)])
        fetcher = described_class.new(source: "cmd:pg_dump --fail")
        expect { fetcher.fetch }.to raise_error(KamalPullPreview::DbError, /Seed command failed/)
      end
    end
  end

  describe "#detect_format" do
    context "when source is a directory" do
      it "returns 'directory'" do
        Dir.mktmpdir do |dir|
          fetcher = described_class.new(source: dir)
          expect(fetcher.detect_format).to eq("directory")
        end
      end
    end

    context "when source is a file with PGDMP header" do
      it "returns 'custom'" do
        Tempfile.create(["dump", ".dump"]) do |f|
          f.write("PGDMP\x00\x00\x00")
          f.flush
          fetcher = described_class.new(source: f.path, format: "auto")
          expect(fetcher.detect_format).to eq("custom")
        end
      end
    end

    context "when source is a file starting with '--'" do
      it "returns 'plain'" do
        Tempfile.create(["dump", ".sql"]) do |f|
          f.write("-- PostgreSQL database dump\n")
          f.flush
          fetcher = described_class.new(source: f.path, format: "auto")
          expect(fetcher.detect_format).to eq("plain")
        end
      end
    end

    context "when source is a file starting with 'BEGIN'" do
      it "returns 'plain'" do
        Tempfile.create(["dump", ".sql"]) do |f|
          f.write("BEGIN;\n")
          f.flush
          fetcher = described_class.new(source: f.path, format: "auto")
          expect(fetcher.detect_format).to eq("plain")
        end
      end
    end

    context "when format is explicitly set (not 'auto')" do
      it "returns the format without inspecting file bytes" do
        fetcher = described_class.new(source: "/nonexistent/path.dump", format: "custom")
        expect(fetcher.detect_format).to eq("custom")
      end
    end

    context "when source is an s3:// URL" do
      it "returns the configured format without inspecting bytes" do
        fetcher = described_class.new(source: "s3://bucket/dump.dump", format: "auto")
        # No file to inspect, so falls back to format value
        expect(fetcher.detect_format).to eq("auto")
      end
    end
  end
end
