# frozen_string_literal: true

require "spec_helper"

RSpec.describe AppStoreConnect::CLI do
  # Create a test private key for the client
  let(:private_key) { OpenSSL::PKey::EC.generate("prime256v1") }

  let(:key_file) do
    file = Tempfile.new(["test_key", ".p8"])
    file.write(private_key.to_pem)
    file.rewind
    file
  end

  before do
    AppStoreConnect.configure do |config|
      config.key_id = "TEST_KEY_ID"
      config.issuer_id = "TEST_ISSUER_ID"
      config.private_key_path = key_file.path
      config.app_id = "123456789"
      config.bundle_id = "com.example.app"
    end
  end

  after do
    key_file.close
    key_file.unlink
  end

  describe "#initialize" do
    it "sets the command from args" do
      cli = described_class.new(["status"])
      expect(cli.instance_variable_get(:@command)).to eq("status")
    end

    it "sets options from remaining args" do
      cli = described_class.new(["status", "--verbose", "--json"])
      expect(cli.instance_variable_get(:@options)).to eq(["--verbose", "--json"])
    end

    it "defaults to status command when no args" do
      cli = described_class.new([])
      expect(cli.instance_variable_get(:@command)).to eq("status")
    end
  end

  describe "#run" do
    context "with unknown command" do
      it "exits with error" do
        cli = described_class.new(["unknown_command"])

        expect { cli.run }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end

      it "outputs error message" do
        cli = described_class.new(["unknown_command"])

        expect { cli.run }.to output(/Unknown command: unknown_command/).to_stdout.and raise_error(SystemExit)
      end
    end

    context "with help command" do
      it "outputs help text" do
        cli = described_class.new(["help"])

        expect { cli.run }.to output(/App Store Connect CLI/).to_stdout
      end

      it "lists available commands" do
        cli = described_class.new(["help"])

        expect { cli.run }.to output(/status.*review.*builds/m).to_stdout
      end
    end

    context "with apps command" do
      before do
        stub_api_get("/apps", response_body: sample_apps_response)
      end

      it "outputs apps list" do
        cli = described_class.new(["apps"])

        expect { cli.run }.to output(/Test App/).to_stdout
      end
    end

    context "with testers command" do
      before do
        stub_api_get(
          "/betaTesters?filter[apps]=123456789&limit=100",
          response_body: sample_beta_testers_response
        )
      end

      it "outputs beta testers list" do
        cli = described_class.new(["testers"])

        expect { cli.run }.to output(/tester@example.com/).to_stdout
      end
    end

    context "with tester-groups command" do
      before do
        stub_api_get(
          "/apps/123456789/betaGroups",
          response_body: sample_beta_groups_response
        )
      end

      it "outputs beta groups list" do
        cli = described_class.new(["tester-groups"])

        expect { cli.run }.to output(/External Testers/).to_stdout
      end
    end

    context "with users command" do
      before do
        stub_api_get("/users?limit=100", response_body: sample_users_response)
      end

      it "outputs users list" do
        cli = described_class.new(["users"])

        expect { cli.run }.to output(/john@example.com/).to_stdout
      end
    end

    context "with territories command" do
      let(:territories_response) do
        {
          data: [
            { id: "USA", type: "territories", attributes: { currency: "USD" } },
            { id: "GBR", type: "territories", attributes: { currency: "GBP" } }
          ]
        }
      end

      before do
        stub_api_get("/territories?limit=200", response_body: territories_response)
      end

      it "outputs territories list" do
        cli = described_class.new(["territories"])

        expect { cli.run }.to output(/USA/).to_stdout
      end
    end

    context "with categories command" do
      let(:categories_response) do
        {
          data: [
            {
              id: "GAMES",
              type: "appCategories",
              attributes: { platforms: ["IOS"] }
            },
            {
              id: "UTILITIES",
              type: "appCategories",
              attributes: { platforms: ["IOS", "MAC_OS"] }
            }
          ]
        }
      end

      before do
        stub_api_get("/appCategories?filter[platforms]=IOS", response_body: categories_response)
      end

      it "outputs categories list" do
        cli = described_class.new(["categories"])

        expect { cli.run }.to output(/GAMES|UTILITIES/).to_stdout
      end
    end

    context "when configuration is missing" do
      before do
        AppStoreConnect.reset_configuration!
      end

      it "exits with error" do
        cli = described_class.new(["apps"])

        expect { cli.run }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end

      it "outputs configuration error message" do
        cli = described_class.new(["apps"])

        expect { cli.run }.to output(/Configuration Error/).to_stdout.and raise_error(SystemExit)
      end
    end

    context "when API returns an error" do
      before do
        stub_api_get(
          "/apps",
          response_body: sample_error_response(
            title: "Not Found",
            detail: "App not found"
          ),
          status: 404
        )
      end

      it "exits with error" do
        cli = described_class.new(["apps"])

        expect { cli.run }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end

      it "outputs API error message" do
        cli = described_class.new(["apps"])

        expect { cli.run }.to output(/API Error/).to_stdout.and raise_error(SystemExit)
      end
    end
  end

  describe "COMMANDS constant" do
    it "includes all expected commands" do
      expected_commands = %w[status review builds apps help testers users territories categories]

      expected_commands.each do |cmd|
        expect(described_class::COMMANDS).to include(cmd)
      end
    end
  end
end
