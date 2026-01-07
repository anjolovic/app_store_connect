# frozen_string_literal: true

module AppStoreConnect
  class Configuration
    attr_accessor :key_id, :issuer_id, :private_key_path,
                  :app_id, :bundle_id

    def initialize
      @key_id = ENV["APP_STORE_CONNECT_KEY_ID"]
      @issuer_id = ENV["APP_STORE_CONNECT_ISSUER_ID"]
      @private_key_path = ENV["APP_STORE_CONNECT_PRIVATE_KEY_PATH"]
      @app_id = ENV["APP_STORE_CONNECT_APP_ID"]
      @bundle_id = ENV["APP_STORE_CONNECT_BUNDLE_ID"]
    end

    def valid?
      !blank?(key_id) && !blank?(issuer_id) && !blank?(private_key_path)
    end

    def missing_keys
      missing = []
      missing << "APP_STORE_CONNECT_KEY_ID" if blank?(key_id)
      missing << "APP_STORE_CONNECT_ISSUER_ID" if blank?(issuer_id)
      missing << "APP_STORE_CONNECT_PRIVATE_KEY_PATH" if blank?(private_key_path)
      missing
    end

    private

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end
  end
end
