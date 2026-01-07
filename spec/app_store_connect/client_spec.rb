# frozen_string_literal: true

require "spec_helper"

RSpec.describe AppStoreConnect::Client do
  # Create a test private key for JWT signing
  let(:private_key) do
    OpenSSL::PKey::EC.generate("prime256v1")
  end

  let(:key_file) do
    file = Tempfile.new(["test_key", ".p8"])
    file.write(private_key.to_pem)
    file.rewind
    file
  end

  let(:client) do
    described_class.new(
      key_id: "TEST_KEY_ID",
      issuer_id: "TEST_ISSUER_ID",
      private_key_path: key_file.path,
      app_id: "123456789",
      bundle_id: "com.example.testapp"
    )
  end

  after do
    key_file.close
    key_file.unlink
  end

  describe "#initialize" do
    it "accepts configuration parameters" do
      expect(client).to be_a(described_class)
    end

    context "with global configuration" do
      before do
        AppStoreConnect.configure do |config|
          config.key_id = "GLOBAL_KEY"
          config.issuer_id = "GLOBAL_ISSUER"
          config.private_key_path = key_file.path
          config.app_id = "987654321"
        end
      end

      it "uses global configuration when no params provided" do
        global_client = described_class.new
        expect(global_client).to be_a(described_class)
      end
    end

    context "with SSL configuration" do
      it "accepts skip_crl_verification option" do
        ssl_client = described_class.new(
          key_id: "TEST_KEY_ID",
          issuer_id: "TEST_ISSUER_ID",
          private_key_path: key_file.path,
          skip_crl_verification: false
        )
        expect(ssl_client).to be_a(described_class)
      end

      it "accepts verify_ssl option" do
        ssl_client = described_class.new(
          key_id: "TEST_KEY_ID",
          issuer_id: "TEST_ISSUER_ID",
          private_key_path: key_file.path,
          verify_ssl: false
        )
        expect(ssl_client).to be_a(described_class)
      end

      it "accepts use_curl option" do
        curl_client = described_class.new(
          key_id: "TEST_KEY_ID",
          issuer_id: "TEST_ISSUER_ID",
          private_key_path: key_file.path,
          use_curl: true
        )
        expect(curl_client).to be_a(described_class)
      end
    end
  end

  describe "#apps" do
    before do
      stub_api_get("/apps", response_body: sample_apps_response)
    end

    it "returns a list of apps" do
      apps = client.apps
      expect(apps).to be_an(Array)
      expect(apps.length).to eq(1)
    end

    it "returns app with correct attributes" do
      app = client.apps.first
      expect(app[:id]).to eq("123456789")
      expect(app[:name]).to eq("Test App")
    end
  end

  describe "#app_store_versions" do
    before do
      stub_api_get(
        "/apps/123456789/appStoreVersions",
        response_body: sample_versions_response
      )
    end

    it "returns a list of versions" do
      versions = client.app_store_versions
      expect(versions).to be_an(Array)
      expect(versions.length).to eq(1)
    end

    it "returns version with correct attributes" do
      version = client.app_store_versions.first
      expect(version["id"]).to eq("ver123")
      expect(version.dig("attributes", "versionString")).to eq("1.0.0")
      expect(version.dig("attributes", "appStoreState")).to eq("READY_FOR_SALE")
    end
  end

  describe "#beta_testers" do
    before do
      stub_api_get(
        "/betaTesters?filter[apps]=123456789&limit=100",
        response_body: sample_beta_testers_response
      )
    end

    it "returns a list of beta testers" do
      testers = client.beta_testers
      expect(testers).to be_an(Array)
      expect(testers.length).to eq(1)
    end

    it "returns tester with correct attributes" do
      tester = client.beta_testers.first
      expect(tester[:id]).to eq("tester123")
      expect(tester[:email]).to eq("tester@example.com")
      expect(tester[:first_name]).to eq("Test")
      expect(tester[:last_name]).to eq("User")
    end
  end

  describe "#create_beta_tester" do
    let(:new_tester_response) do
      {
        data: {
          id: "new_tester123",
          type: "betaTesters",
          attributes: {
            email: "new@example.com",
            firstName: "New",
            lastName: "Tester",
            inviteType: "EMAIL",
            betaTestersState: "INVITED"
          }
        }
      }
    end

    before do
      stub_api_post("/betaTesters", response_body: new_tester_response)
    end

    it "creates a new beta tester" do
      result = client.create_beta_tester(
        email: "new@example.com",
        first_name: "New",
        last_name: "Tester"
      )

      expect(result[:id]).to eq("new_tester123")
      expect(result[:email]).to eq("new@example.com")
      expect(result[:state]).to eq("INVITED")
    end
  end

  describe "#delete_beta_tester" do
    before do
      stub_api_delete("/betaTesters/tester123")
    end

    it "deletes the beta tester" do
      expect { client.delete_beta_tester(tester_id: "tester123") }.not_to raise_error
    end
  end

  describe "#beta_groups" do
    before do
      stub_api_get(
        "/apps/123456789/betaGroups",
        response_body: sample_beta_groups_response
      )
    end

    it "returns a list of beta groups" do
      groups = client.beta_groups
      expect(groups).to be_an(Array)
      expect(groups.length).to eq(1)
    end

    it "returns group with correct attributes" do
      group = client.beta_groups.first
      expect(group[:id]).to eq("group123")
      expect(group[:name]).to eq("External Testers")
      expect(group[:is_internal]).to be false
      expect(group[:public_link_enabled]).to be true
    end
  end

  describe "#create_beta_group" do
    let(:new_group_response) do
      {
        data: {
          id: "new_group123",
          type: "betaGroups",
          attributes: {
            name: "New Group",
            isInternalGroup: false,
            publicLinkEnabled: false,
            createdDate: "2025-01-06T00:00:00Z"
          }
        }
      }
    end

    before do
      stub_api_post("/betaGroups", response_body: new_group_response)
    end

    it "creates a new beta group" do
      result = client.create_beta_group(name: "New Group")

      expect(result[:id]).to eq("new_group123")
      expect(result[:name]).to eq("New Group")
    end
  end

  describe "#users" do
    before do
      stub_api_get("/users?limit=100", response_body: sample_users_response)
    end

    it "returns a list of users" do
      users = client.users
      expect(users).to be_an(Array)
      expect(users.length).to eq(1)
    end

    it "returns user with correct attributes" do
      user = client.users.first
      expect(user[:id]).to eq("user123")
      expect(user[:email]).to eq("john@example.com")
      expect(user[:first_name]).to eq("John")
      expect(user[:last_name]).to eq("Doe")
      expect(user[:roles]).to eq(["APP_MANAGER", "DEVELOPER"])
    end
  end

  describe "#create_user_invitation" do
    let(:invitation_response) do
      {
        data: {
          id: "invite123",
          type: "userInvitations",
          attributes: {
            email: "invite@example.com",
            firstName: "Invited",
            lastName: "User",
            roles: ["DEVELOPER"],
            expirationDate: "2025-02-06T00:00:00Z"
          }
        }
      }
    end

    before do
      stub_api_post("/userInvitations", response_body: invitation_response)
    end

    it "creates a user invitation" do
      result = client.create_user_invitation(
        email: "invite@example.com",
        first_name: "Invited",
        last_name: "User",
        roles: ["DEVELOPER"]
      )

      expect(result[:id]).to eq("invite123")
      expect(result[:email]).to eq("invite@example.com")
      expect(result[:roles]).to eq(["DEVELOPER"])
    end
  end

  describe "#territories" do
    let(:territories_response) do
      {
        data: [
          { id: "USA", type: "territories", attributes: { currency: "USD" } },
          { id: "GBR", type: "territories", attributes: { currency: "GBP" } },
          { id: "JPN", type: "territories", attributes: { currency: "JPY" } }
        ]
      }
    end

    before do
      stub_api_get("/territories?limit=200", response_body: territories_response)
    end

    it "returns a list of territories" do
      territories = client.territories
      expect(territories).to be_an(Array)
      expect(territories.length).to eq(3)
    end

    it "returns territory with correct attributes" do
      territory = client.territories.first
      expect(territory[:id]).to eq("USA")
      expect(territory[:currency]).to eq("USD")
    end
  end

  describe "error handling" do
    context "when API returns an error" do
      before do
        stub_api_get(
          "/apps",
          response_body: sample_error_response(
            title: "Authentication Error",
            detail: "Invalid API key"
          ),
          status: 401
        )
      end

      it "raises ApiError with error details" do
        expect { client.apps }.to raise_error(
          AppStoreConnect::ApiError,
          /Unauthorized/
        )
      end
    end
  end

  describe "#generate_token" do
    it "generates a valid JWT token" do
      token = client.send(:generate_token)
      expect(token).to be_a(String)
      expect(token.split(".").length).to eq(3) # JWT has 3 parts
    end

    it "includes correct claims" do
      token = client.send(:generate_token)
      payload = JWT.decode(token, nil, false).first

      expect(payload["iss"]).to eq("TEST_ISSUER_ID")
      expect(payload["aud"]).to eq("appstoreconnect-v1")
      expect(payload["exp"]).to be > Time.now.to_i
    end
  end
end
