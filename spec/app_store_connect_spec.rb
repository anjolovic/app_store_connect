# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AppStoreConnect do
  describe '.configuration' do
    it 'returns a Configuration instance' do
      expect(described_class.configuration).to be_a(AppStoreConnect::Configuration)
    end

    it 'returns the same instance on multiple calls' do
      config1 = described_class.configuration
      config2 = described_class.configuration
      expect(config1).to be(config2)
    end
  end

  describe '.configure' do
    it 'yields the configuration' do
      expect { |b| described_class.configure(&b) }.to yield_with_args(AppStoreConnect::Configuration)
    end

    it 'allows setting configuration values' do
      described_class.configure do |config|
        config.key_id = 'test_key'
        config.issuer_id = 'test_issuer'
        config.app_id = '123456789'
      end

      expect(described_class.configuration.key_id).to eq('test_key')
      expect(described_class.configuration.issuer_id).to eq('test_issuer')
      expect(described_class.configuration.app_id).to eq('123456789')
    end
  end

  describe '.reset_configuration!' do
    before do
      described_class.configure do |config|
        config.key_id = 'test_key'
        config.issuer_id = 'test_issuer'
      end
    end

    it 'resets configuration to defaults' do
      described_class.reset_configuration!

      # After reset, values should be nil (or from ENV which we cleared in spec_helper)
      expect(described_class.configuration.key_id).to be_nil
      expect(described_class.configuration.issuer_id).to be_nil
    end

    it 'creates a new configuration instance' do
      old_config = described_class.configuration
      described_class.reset_configuration!
      new_config = described_class.configuration

      expect(new_config).not_to be(old_config)
    end
  end

  describe 'VERSION' do
    it 'has a version number' do
      expect(AppStoreConnect::VERSION).not_to be_nil
    end

    it 'is a valid version format' do
      expect(AppStoreConnect::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
    end
  end

  describe 'ApiError' do
    it 'is defined' do
      expect(AppStoreConnect::ApiError).to be_a(Class)
    end

    it 'inherits from StandardError' do
      expect(AppStoreConnect::ApiError.ancestors).to include(StandardError)
    end
  end
end
