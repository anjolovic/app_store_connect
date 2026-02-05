# frozen_string_literal: true

if ENV['SIMPLECOV'] == '1'
  require 'simplecov'
  SimpleCov.start do
    add_filter '/spec/'
    add_group 'Client', 'lib/app_store_connect/client'
    add_group 'CLI', 'lib/app_store_connect/cli.rb'
    add_group 'Core', ['lib/app_store_connect.rb', 'lib/app_store_connect/configuration.rb']
  end
end

require 'app_store_connect'
require 'webmock/rspec'

# Disable external connections
WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.warnings = true

  config.default_formatter = 'doc' if config.files_to_run.one?

  config.order = :random
  Kernel.srand config.seed

  # Reset configuration before each test
  config.before do
    AppStoreConnect.reset_configuration!
  end

  # Some specs intentionally raise/rescue SystemExit. Ruby can retain the last
  # exception in $ERROR_INFO even when it's expected, which can cause processes
  # to exit non-zero despite a passing suite.
  config.after do
    $ERROR_INFO = nil
  end

  config.after(:suite) do
    $ERROR_INFO = nil
  end

end

# Helper to stub App Store Connect API responses
module ApiHelpers
  BASE_URL = 'https://api.appstoreconnect.apple.com/v1'

  def stub_api_request(method, path, response_body:, status: 200)
    # Match URL with any query params - use regex for flexible matching
    # Replace query string delimiters for regex matching
    escaped_base = Regexp.escape(BASE_URL)
    # Escape path but convert special chars like [ ] to match both encoded and unencoded
    escaped_path = Regexp.escape(path)
                         .gsub('\\[', '[\\[%5B]')
                         .gsub('\\]', '[\\]%5D]')
                         .gsub('\\?', '\\?')

    url_pattern = Regexp.new("#{escaped_base}#{escaped_path}")

    stub_request(method, url_pattern)
      .to_return(
        status: status,
        body: response_body.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_api_get(path, response_body:, status: 200)
    stub_api_request(:get, path, response_body: response_body, status: status)
  end

  def stub_api_post(path, response_body:, status: 201)
    stub_api_request(:post, path, response_body: response_body, status: status)
  end

  def stub_api_patch(path, response_body:, status: 200)
    stub_api_request(:patch, path, response_body: response_body, status: status)
  end

  def stub_api_delete(path, status: 204)
    escaped_base = Regexp.escape(BASE_URL)
    escaped_path = Regexp.escape(path)
    url_pattern = Regexp.new("#{escaped_base}#{escaped_path}")
    stub_request(:delete, url_pattern)
      .to_return(status: status, body: '', headers: {})
  end

  # Sample API responses
  def sample_app_response
    {
      data: {
        id: '123456789',
        type: 'apps',
        attributes: {
          name: 'Test App',
          bundleId: 'com.example.testapp',
          sku: 'TESTAPP001',
          primaryLocale: 'en-US'
        }
      }
    }
  end

  def sample_apps_response
    {
      data: [sample_app_response[:data]]
    }
  end

  def sample_version_response
    {
      data: {
        id: 'ver123',
        type: 'appStoreVersions',
        attributes: {
          versionString: '1.0.0',
          appStoreState: 'READY_FOR_SALE',
          platform: 'IOS',
          releaseType: 'AFTER_APPROVAL'
        }
      }
    }
  end

  def sample_versions_response
    {
      data: [sample_version_response[:data]]
    }
  end

  def sample_beta_tester_response
    {
      data: {
        id: 'tester123',
        type: 'betaTesters',
        attributes: {
          email: 'tester@example.com',
          firstName: 'Test',
          lastName: 'User',
          inviteType: 'EMAIL',
          betaTestersState: 'INSTALLED'
        }
      }
    }
  end

  def sample_beta_testers_response
    {
      data: [sample_beta_tester_response[:data]]
    }
  end

  def sample_beta_group_response
    {
      data: {
        id: 'group123',
        type: 'betaGroups',
        attributes: {
          name: 'External Testers',
          isInternalGroup: false,
          publicLinkEnabled: true,
          publicLink: 'https://testflight.apple.com/join/ABC123',
          createdDate: '2025-01-01T00:00:00Z'
        }
      }
    }
  end

  def sample_beta_groups_response
    {
      data: [sample_beta_group_response[:data]]
    }
  end

  def sample_user_response
    {
      data: {
        id: 'user123',
        type: 'users',
        attributes: {
          username: 'jdoe',
          firstName: 'John',
          lastName: 'Doe',
          email: 'john@example.com',
          roles: %w[APP_MANAGER DEVELOPER],
          allAppsVisible: true,
          provisioningAllowed: false
        }
      }
    }
  end

  def sample_users_response
    {
      data: [sample_user_response[:data]]
    }
  end

  def sample_error_response(title: 'Error', detail: 'Something went wrong')
    {
      errors: [
        {
          status: '400',
          title: title,
          detail: detail
        }
      ]
    }
  end
end

RSpec.configure do |config|
  config.include ApiHelpers
end
