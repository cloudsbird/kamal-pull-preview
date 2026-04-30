# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe KamalPullPreview::CLI do
  describe "init" do
    around do |example|
      Dir.mktmpdir do |tmpdir|
        Dir.chdir(tmpdir) { example.run }
      end
    end

    it "creates kamal-pull-preview.yml if it does not exist" do
      described_class.new.init
      expect(File.exist?("kamal-pull-preview.yml")).to be true
    end

    it "creates .github/workflows/pull-preview.yml if it does not exist" do
      described_class.new.init
      expect(File.exist?(".github/workflows/pull-preview.yml")).to be true
    end

    it "skips kamal-pull-preview.yml with a warning if it already exists" do
      File.write("kamal-pull-preview.yml", "existing content")
      expect { described_class.new.init }.to output(/Skipped.*kamal-pull-preview\.yml/).to_stdout
      expect(File.read("kamal-pull-preview.yml")).to eq("existing content")
    end

    it "skips workflow file with a warning if it already exists" do
      FileUtils.mkdir_p(".github/workflows")
      File.write(".github/workflows/pull-preview.yml", "existing content")
      expect { described_class.new.init }.to output(/Skipped.*pull-preview\.yml/).to_stdout
      expect(File.read(".github/workflows/pull-preview.yml")).to eq("existing content")
    end
  end

  describe "cleanup" do
    let(:cleaner) { instance_double(KamalPullPreview::Cleaner) }

    before do
      allow(KamalPullPreview::Cleaner).to receive(:new).and_return(cleaner)
    end

    it "calls Cleaner#cleanup_expired and prints count when previews removed" do
      allow(cleaner).to receive(:cleanup_expired).and_return(3)
      expect { described_class.new.cleanup }.to output(/Removed 3 expired preview/).to_stdout
    end

    it "prints 'No expired previews found' when count is zero" do
      allow(cleaner).to receive(:cleanup_expired).and_return(0)
      expect { described_class.new.cleanup }.to output(/No expired previews found/).to_stdout
    end

    it "exits 1 on ConfigError" do
      allow(cleaner).to receive(:cleanup_expired).and_raise(KamalPullPreview::ConfigError, "missing config")
      expect { described_class.new.cleanup }.to raise_error(SystemExit) do |e|
        expect(e.status).to eq(1)
      end
    end
  end
end
