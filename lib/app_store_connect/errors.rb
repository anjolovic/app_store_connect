# frozen_string_literal: true

module AppStoreConnect
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class ApiError < Error; end
end
