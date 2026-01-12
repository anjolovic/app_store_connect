# frozen_string_literal: true

module AppStoreConnect
  class Configuration
    attr_accessor :key_id, :issuer_id, :private_key_path,
                  :app_id, :bundle_id,
                  :skip_crl_verification, :verify_ssl, :use_curl

    def initialize
      @key_id = ENV.fetch('APP_STORE_CONNECT_KEY_ID', nil)
      @issuer_id = ENV.fetch('APP_STORE_CONNECT_ISSUER_ID', nil)
      @private_key_path = ENV.fetch('APP_STORE_CONNECT_PRIVATE_KEY_PATH', nil)
      @app_id = ENV.fetch('APP_STORE_CONNECT_APP_ID', nil)
      @bundle_id = ENV.fetch('APP_STORE_CONNECT_BUNDLE_ID', nil)

      # SSL configuration - defaults handle CRL issues with Apple certificates
      @skip_crl_verification = true  # Skip CRL checks that often fail with Apple
      @verify_ssl = true             # Still verify SSL certificates
      @use_curl = false              # Use Net::HTTP by default, curl as fallback
    end

    def valid?
      !blank?(key_id) && !blank?(issuer_id) && !blank?(private_key_path)
    end

    def missing_keys
      missing = []
      missing << 'APP_STORE_CONNECT_KEY_ID' if blank?(key_id)
      missing << 'APP_STORE_CONNECT_ISSUER_ID' if blank?(issuer_id)
      missing << 'APP_STORE_CONNECT_PRIVATE_KEY_PATH' if blank?(private_key_path)
      missing
    end

    private

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end
  end
end
