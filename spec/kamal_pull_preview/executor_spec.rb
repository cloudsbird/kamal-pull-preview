# frozen_string_literal: true

require "spec_helper"

RSpec.describe KamalPullPreview::Executor do
  before do
    described_class.dry_run = false
  end

  after do
    described_class.dry_run = false
  end

  describe ".execute" do
    context "when command succeeds" do
      before do
        allow(described_class).to receive(:system).and_return(true)
        allow(Process).to receive(:last_status).and_return(instance_double(Process::Status, success?: true, exitstatus: 0))
      end

      it "returns without raising" do
        expect { described_class.execute("echo", "hello") }.not_to raise_error
      end

      it "logs the command" do
        expect(KamalPullPreview.logger).to receive(:info).with(/Executing: echo hello/)
        described_class.execute("echo", "hello")
      end
    end

    context "when command fails" do
      before do
        allow(described_class).to receive(:system).and_return(false)
        allow(Process).to receive(:last_status).and_return(instance_double(Process::Status, success?: false, exitstatus: 1))
      end

      it "raises DeployError" do
        expect {
          described_class.execute("false")
        }.to raise_error(KamalPullPreview::DeployError, /exit 1/)
      end

      it "retries up to the default retry count and then raises" do
        expect(described_class).to receive(:system).exactly(3).times.and_return(false)
        allow(Process).to receive(:last_status).and_return(instance_double(Process::Status, success?: false, exitstatus: 1))

        expect {
          described_class.execute("false", retries: 2)
        }.to raise_error(KamalPullPreview::DeployError)
      end
    end

    context "when command is not found (status nil)" do
      before do
        allow(described_class).to receive(:system).and_return(nil)
        allow(Process).to receive(:last_status).and_return(nil)
      end

      it "raises DeployError" do
        expect {
          described_class.execute("nonexistent_command")
        }.to raise_error(KamalPullPreview::DeployError, /not found/)
      end
    end

    context "in dry-run mode" do
      before { described_class.dry_run = true }

      it "logs the command without executing" do
        expect(described_class).not_to receive(:system)
        expect(KamalPullPreview.logger).to receive(:info).with(/\[dry-run\]/)
        described_class.execute("echo", "hello")
      end
    end

    context "when timeout is exceeded" do
      it "raises DeployError" do
        expect {
          described_class.execute("sleep", "2", timeout: 0.1)
        }.to raise_error(KamalPullPreview::DeployError, /timed out/)
      end
    end
  end

  describe ".capture" do
    it "returns stdout as a String" do
      out = described_class.capture("echo", "captured")
      expect(out.strip).to eq("captured")
    end
  end

  describe ".capture2" do
    it "returns stdout and status" do
      out, status = described_class.capture2("echo", "captured")
      expect(out.strip).to eq("captured")
      expect(status).to be_a(Process::Status)
      expect(status.success?).to be true
    end
  end
end
