# frozen_string_literal: true

require_relative 'app_store_connect/version'
require_relative 'app_store_connect/errors'
require_relative 'app_store_connect/configuration'
require_relative 'app_store_connect/http_client'
require_relative 'app_store_connect/client'
require_relative 'app_store_connect/cli'

module AppStoreConnect
  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
