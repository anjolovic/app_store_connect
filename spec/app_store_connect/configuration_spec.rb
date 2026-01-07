# frozen_string_literal: true

require "spec_helper"

RSpec.describe AppStoreConnect::Configuration do
  subject(:config) { described_class.new }

  describe "#initialize" do
    context "when environment variables are set" do
      before do
        ENV["APP_STORE_CONNECT_KEY_ID"] = "test_key_id"
        ENV["APP_STORE_CONNECT_ISSUER_ID"] = "test_issuer_id"
        ENV["APP_STORE_CONNECT_PRIVATE_KEY_PATH"] = "/path/to/key.p8"
        ENV["APP_STORE_CONNECT_APP_ID"] = "123456789"
        ENV["APP_STORE_CONNECT_BUNDLE_ID"] = "com.example.app"
      end

      after do
        ENV.delete("APP_STORE_CONNECT_KEY_ID")
        ENV.delete("APP_STORE_CONNECT_ISSUER_ID")
        ENV.delete("APP_STORE_CONNECT_PRIVATE_KEY_PATH")
        ENV.delete("APP_STORE_CONNECT_APP_ID")
        ENV.delete("APP_STORE_CONNECT_BUNDLE_ID")
      end

      it "reads key_id from environment" do
        expect(config.key_id).to eq("test_key_id")
      end

      it "reads issuer_id from environment" do
        expect(config.issuer_id).to eq("test_issuer_id")
      end

      it "reads private_key_path from environment" do
        expect(config.private_key_path).to eq("/path/to/key.p8")
      end

      it "reads app_id from environment" do
        expect(config.app_id).to eq("123456789")
      end

      it "reads bundle_id from environment" do
        expect(config.bundle_id).to eq("com.example.app")
      end
    end

    context "when environment variables are not set" do
      before do
        ENV.delete("APP_STORE_CONNECT_KEY_ID")
        ENV.delete("APP_STORE_CONNECT_ISSUER_ID")
        ENV.delete("APP_STORE_CONNECT_PRIVATE_KEY_PATH")
        ENV.delete("APP_STORE_CONNECT_APP_ID")
        ENV.delete("APP_STORE_CONNECT_BUNDLE_ID")
      end

      it "returns nil for key_id" do
        expect(config.key_id).to be_nil
      end

      it "returns nil for issuer_id" do
        expect(config.issuer_id).to be_nil
      end

      it "returns nil for private_key_path" do
        expect(config.private_key_path).to be_nil
      end
    end
  end

  describe "#valid?" do
    context "when all required keys are present" do
      before do
        config.key_id = "key"
        config.issuer_id = "issuer"
        config.private_key_path = "/path/to/key.p8"
      end

      it "returns true" do
        expect(config.valid?).to be true
      end
    end

    context "when key_id is missing" do
      before do
        config.key_id = nil
        config.issuer_id = "issuer"
        config.private_key_path = "/path/to/key.p8"
      end

      it "returns false" do
        expect(config.valid?).to be false
      end
    end

    context "when issuer_id is missing" do
      before do
        config.key_id = "key"
        config.issuer_id = nil
        config.private_key_path = "/path/to/key.p8"
      end

      it "returns false" do
        expect(config.valid?).to be false
      end
    end

    context "when private_key_path is missing" do
      before do
        config.key_id = "key"
        config.issuer_id = "issuer"
        config.private_key_path = nil
      end

      it "returns false" do
        expect(config.valid?).to be false
      end
    end

    context "when key_id is empty string" do
      before do
        config.key_id = ""
        config.issuer_id = "issuer"
        config.private_key_path = "/path/to/key.p8"
      end

      it "returns false" do
        expect(config.valid?).to be false
      end
    end
  end

  describe "#missing_keys" do
    context "when all keys are present" do
      before do
        config.key_id = "key"
        config.issuer_id = "issuer"
        config.private_key_path = "/path/to/key.p8"
      end

      it "returns empty array" do
        expect(config.missing_keys).to eq([])
      end
    end

    context "when key_id is missing" do
      before do
        config.key_id = nil
        config.issuer_id = "issuer"
        config.private_key_path = "/path/to/key.p8"
      end

      it "returns array with APP_STORE_CONNECT_KEY_ID" do
        expect(config.missing_keys).to eq(["APP_STORE_CONNECT_KEY_ID"])
      end
    end

    context "when all keys are missing" do
      before do
        config.key_id = nil
        config.issuer_id = nil
        config.private_key_path = nil
      end

      it "returns all missing keys" do
        expect(config.missing_keys).to contain_exactly(
          "APP_STORE_CONNECT_KEY_ID",
          "APP_STORE_CONNECT_ISSUER_ID",
          "APP_STORE_CONNECT_PRIVATE_KEY_PATH"
        )
      end
    end
  end

  describe "SSL configuration" do
    describe "#skip_crl_verification" do
      it "defaults to true" do
        expect(config.skip_crl_verification).to be true
      end

      it "can be set to false" do
        config.skip_crl_verification = false
        expect(config.skip_crl_verification).to be false
      end
    end

    describe "#verify_ssl" do
      it "defaults to true" do
        expect(config.verify_ssl).to be true
      end

      it "can be set to false" do
        config.verify_ssl = false
        expect(config.verify_ssl).to be false
      end
    end

    describe "#use_curl" do
      it "defaults to false" do
        expect(config.use_curl).to be false
      end

      it "can be set to true" do
        config.use_curl = true
        expect(config.use_curl).to be true
      end
    end
  end
end
