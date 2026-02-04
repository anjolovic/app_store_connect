# frozen_string_literal: true

require 'jwt'
require 'json'
require 'uri'
require 'openssl'
require 'time'
require 'digest'
require 'base64'
require 'tempfile'

# Load client modules
require_relative 'client/apps'
require_relative 'client/subscriptions'
require_relative 'client/in_app_purchases'
require_relative 'client/customer_reviews'
require_relative 'client/releases'
require_relative 'client/test_flight'
require_relative 'client/pricing'
require_relative 'client/users'
require_relative 'client/screenshots'
require_relative 'client/privacy'
require_relative 'session'

module AppStoreConnect
  # App Store Connect API client for checking app status, review submissions,
  # in-app purchases, and other App Store Connect data.
  #
  # Usage:
  #   client = AppStoreConnect::Client.new
  #   client.apps                    # List all apps
  #   client.app_status              # Get app status summary
  #   client.review_status           # Check current review submission status
  #   client.subscriptions           # List all subscription products
  #   client.builds                  # List recent builds
  #
  # Configuration:
  #   Set these environment variables:
  #   - APP_STORE_CONNECT_KEY_ID: Your App Store Connect API Key ID
  #   - APP_STORE_CONNECT_ISSUER_ID: Your Issuer ID (same for all keys)
  #   - APP_STORE_CONNECT_PRIVATE_KEY_PATH: Path to the .p8 key file
  #   - APP_STORE_CONNECT_APP_ID: Your app's Apple ID
  #   - APP_STORE_CONNECT_BUNDLE_ID: Your app's bundle identifier
  #
  #   Or configure programmatically:
  #     AppStoreConnect.configure do |config|
  #       config.app_id = "123456789"
  #       config.bundle_id = "com.example.app"
  #     end
  #
  class Client
    BASE_URL = 'https://api.appstoreconnect.apple.com/v1'
    IRIS_URL = 'https://appstoreconnect.apple.com/iris/v1'

    # Include domain-specific modules
    include Apps
    include Subscriptions
    include InAppPurchases
    include CustomerReviews
    include Releases
    include TestFlight
    include Pricing
    include Users
    include Screenshots
    include Privacy

    def initialize(
      key_id: nil,
      issuer_id: nil,
      private_key_path: nil,
      app_id: nil,
      bundle_id: nil,
      http_client: nil,
      skip_crl_verification: nil,
      verify_ssl: nil,
      use_curl: nil,
      upload_retries: nil,
      upload_retry_sleep: nil
    )
      config = AppStoreConnect.configuration

      @key_id = key_id || config.key_id
      @issuer_id = issuer_id || config.issuer_id
      @private_key_path = private_key_path || config.private_key_path
      @app_id = app_id || config.app_id
      @bundle_id = bundle_id || config.bundle_id

      # SSL configuration - use provided values or fall back to config
      skip_crl = skip_crl_verification.nil? ? config.skip_crl_verification : skip_crl_verification
      verify = verify_ssl.nil? ? config.verify_ssl : verify_ssl
      curl = use_curl.nil? ? config.use_curl : use_curl

      # Upload robustness (multipart PUT to uploadOperations URLs)
      @upload_retries = upload_retries.nil? ? config.upload_retries : upload_retries
      @upload_retry_sleep = upload_retry_sleep.nil? ? config.upload_retry_sleep : upload_retry_sleep

      @http_client = http_client || build_http_client(
        skip_crl_verification: skip_crl,
        verify_ssl: verify,
        use_curl: curl
      )

      @skip_crl_verification = skip_crl
      @verify_ssl = verify

      # Initialize session for IRIS API (Resolution Center)
      @session = Session.new

      validate_configuration!
    end

    attr_reader :app_id, :bundle_id, :session

    # Check if session-based auth is available (for Resolution Center access)
    def session_available?
      @session&.valid?
    end

    # ─────────────────────────────────────────────────────────────────────────
    # App Store Version Localizations
    # ─────────────────────────────────────────────────────────────────────────

    # Get app store version localizations (app description, what's new, keywords)
    def app_store_version_localizations(version_id:)
      get("/appStoreVersions/#{version_id}/appStoreVersionLocalizations")['data'].map do |loc|
        {
          id: loc['id'],
          locale: loc.dig('attributes', 'locale'),
          description: loc.dig('attributes', 'description'),
          keywords: loc.dig('attributes', 'keywords'),
          whats_new: loc.dig('attributes', 'whatsNew'),
          promotional_text: loc.dig('attributes', 'promotionalText'),
          marketing_url: loc.dig('attributes', 'marketingUrl'),
          support_url: loc.dig('attributes', 'supportUrl')
        }
      end
    end

    # Update app store version localization (description, what's new, etc.)
    def update_app_store_version_localization(localization_id:, description: nil, whats_new: nil,
                                              keywords: nil, promotional_text: nil,
                                              marketing_url: nil, support_url: nil)
      attributes = {}
      attributes[:description] = description if description
      attributes[:whatsNew] = whats_new if whats_new
      attributes[:keywords] = keywords if keywords
      attributes[:promotionalText] = promotional_text if promotional_text
      attributes[:marketingUrl] = marketing_url if marketing_url
      attributes[:supportUrl] = support_url if support_url

      return nil if attributes.empty?

      patch("/appStoreVersionLocalizations/#{localization_id}", body: {
              data: {
                type: 'appStoreVersionLocalizations',
                id: localization_id,
                attributes: attributes
              }
            })
    end

    # Get app infos
    def app_infos(target_app_id: nil)
      target_app_id ||= @app_id
      get("/apps/#{target_app_id}/appInfos")['data']
    end

    # ─────────────────────────────────────────────────────────────────────────
    # Review Detail Methods
    # ─────────────────────────────────────────────────────────────────────────

    # Update beta app review detail (contact info, demo account, notes)
    def update_beta_app_review_detail(detail_id:, contact_first_name: nil, contact_last_name: nil,
                                      contact_phone: nil, contact_email: nil,
                                      demo_account_name: nil, demo_account_password: nil,
                                      demo_account_required: nil, notes: nil)
      attributes = {}
      attributes[:contactFirstName] = contact_first_name if contact_first_name
      attributes[:contactLastName] = contact_last_name if contact_last_name
      attributes[:contactPhone] = contact_phone if contact_phone
      attributes[:contactEmail] = contact_email if contact_email
      attributes[:demoAccountName] = demo_account_name if demo_account_name
      attributes[:demoAccountPassword] = demo_account_password if demo_account_password
      attributes[:demoAccountRequired] = demo_account_required unless demo_account_required.nil?
      attributes[:notes] = notes if notes

      return nil if attributes.empty?

      patch("/betaAppReviewDetails/#{detail_id}", body: {
              data: {
                type: 'betaAppReviewDetails',
                id: detail_id,
                attributes: attributes
              }
            })
    end

    # Get app store review detail for a version
    def app_store_review_detail(version_id:)
      result = get("/appStoreVersions/#{version_id}/appStoreReviewDetail")['data']
      return nil unless result

      {
        id: result['id'],
        contact_first_name: result.dig('attributes', 'contactFirstName'),
        contact_last_name: result.dig('attributes', 'contactLastName'),
        contact_phone: result.dig('attributes', 'contactPhone'),
        contact_email: result.dig('attributes', 'contactEmail'),
        demo_account_name: result.dig('attributes', 'demoAccountName'),
        demo_account_password: result.dig('attributes', 'demoAccountPassword'),
        demo_account_required: result.dig('attributes', 'demoAccountRequired'),
        notes: result.dig('attributes', 'notes')
      }
    rescue ApiError => e
      return nil if e.message.include?('Not found')

      raise
    end

    # Create app store review detail for a version
    def create_app_store_review_detail(version_id:, contact_first_name: nil, contact_last_name: nil,
                                       contact_phone: nil, contact_email: nil,
                                       demo_account_name: nil, demo_account_password: nil,
                                       demo_account_required: nil, notes: nil)
      attributes = {}
      attributes[:contactFirstName] = contact_first_name if contact_first_name
      attributes[:contactLastName] = contact_last_name if contact_last_name
      attributes[:contactPhone] = contact_phone if contact_phone
      attributes[:contactEmail] = contact_email if contact_email
      attributes[:demoAccountName] = demo_account_name if demo_account_name
      attributes[:demoAccountPassword] = demo_account_password if demo_account_password
      attributes[:demoAccountRequired] = demo_account_required unless demo_account_required.nil?
      attributes[:notes] = notes if notes

      result = post('/appStoreReviewDetails', body: {
                      data: {
                        type: 'appStoreReviewDetails',
                        attributes: attributes,
                        relationships: {
                          appStoreVersion: {
                            data: {
                              type: 'appStoreVersions',
                              id: version_id
                            }
                          }
                        }
                      }
                    })

      {
        id: result['data']['id'],
        notes: result['data'].dig('attributes', 'notes')
      }
    end

    # Update app store review detail (contact info, demo account for App Review)
    def update_app_store_review_detail(detail_id:, contact_first_name: nil, contact_last_name: nil,
                                       contact_phone: nil, contact_email: nil,
                                       demo_account_name: nil, demo_account_password: nil,
                                       demo_account_required: nil, notes: nil)
      attributes = {}
      attributes[:contactFirstName] = contact_first_name if contact_first_name
      attributes[:contactLastName] = contact_last_name if contact_last_name
      attributes[:contactPhone] = contact_phone if contact_phone
      attributes[:contactEmail] = contact_email if contact_email
      attributes[:demoAccountName] = demo_account_name if demo_account_name
      attributes[:demoAccountPassword] = demo_account_password if demo_account_password
      attributes[:demoAccountRequired] = demo_account_required unless demo_account_required.nil?
      attributes[:notes] = notes if notes

      return nil if attributes.empty?

      patch("/appStoreReviewDetails/#{detail_id}", body: {
              data: {
                type: 'appStoreReviewDetails',
                id: detail_id,
                attributes: attributes
              }
            })
    end

    # Submit a version for review
    def create_review_submission(platform: 'IOS', target_app_id: nil)
      target_app_id ||= @app_id
      post('/reviewSubmissions', body: {
             data: {
               type: 'reviewSubmissions',
               attributes: {
                 platform: platform
               },
               relationships: {
                 app: {
                   data: {
                     type: 'apps',
                     id: target_app_id
                   }
                 }
               }
             }
           })
    end

    # Cancel a pending review submission
    def cancel_review_submission(submission_id:)
      patch("/reviewSubmissions/#{submission_id}", body: {
              data: {
                type: 'reviewSubmissions',
                id: submission_id,
                attributes: {
                  canceled: true
                }
              }
            })
    end

    # ─────────────────────────────────────────────────────────────────────────
    # Content Rights Declaration
    # ─────────────────────────────────────────────────────────────────────────

    # Get content rights declaration for a version
    # Returns whether app uses third-party content and if rights are declared
    def content_rights_declaration(version_id:)
      result = get("/appStoreVersions/#{version_id}")['data']
      return nil unless result

      {
        id: result['id'],
        version_string: result.dig('attributes', 'versionString'),
        uses_third_party_content: result.dig('attributes', 'usesThirdPartyContent'),
        # If usesThirdPartyContent is true, user must confirm they have rights
        state: result.dig('attributes', 'appStoreState')
      }
    end

    # Update content rights declaration
    # uses_third_party_content: true if app contains/displays/accesses third-party content
    def update_content_rights(version_id:, uses_third_party_content:)
      patch("/appStoreVersions/#{version_id}", body: {
              data: {
                type: 'appStoreVersions',
                id: version_id,
                attributes: {
                  usesThirdPartyContent: uses_third_party_content
                }
              }
            })
    end

    # ─────────────────────────────────────────────────────────────────────────
    # App Info Methods
    # ─────────────────────────────────────────────────────────────────────────

    # Get app info (primary category, age rating, etc.)
    def app_info(target_app_id: nil)
      target_app_id ||= @app_id
      result = get("/apps/#{target_app_id}/appInfos")['data']
      return [] if result.empty?

      result.map do |info|
        {
          id: info['id'],
          state: info.dig('attributes', 'appStoreState'),
          app_store_age_rating: info.dig('attributes', 'appStoreAgeRating'),
          brazil_age_rating: info.dig('attributes', 'brazilAgeRating'),
          brazil_age_rating_v2: info.dig('attributes', 'brazilAgeRatingV2'),
          kids_age_band: info.dig('attributes', 'kidsAgeBand')
        }
      end
    end

    # Get app info localizations (app name, subtitle, privacy policy URL)
    def app_info_localizations(app_info_id:)
      get("/appInfos/#{app_info_id}/appInfoLocalizations")['data'].map do |loc|
        {
          id: loc['id'],
          locale: loc.dig('attributes', 'locale'),
          name: loc.dig('attributes', 'name'),
          subtitle: loc.dig('attributes', 'subtitle'),
          privacy_policy_url: loc.dig('attributes', 'privacyPolicyUrl'),
          privacy_choices_url: loc.dig('attributes', 'privacyChoicesUrl'),
          privacy_policy_text: loc.dig('attributes', 'privacyPolicyText')
        }
      end
    end

    # Update app info localization
    def update_app_info_localization(localization_id:, name: nil, subtitle: nil,
                                     privacy_policy_url: nil, privacy_choices_url: nil,
                                     privacy_policy_text: nil)
      attributes = {}
      attributes[:name] = name if name
      attributes[:subtitle] = subtitle if subtitle
      attributes[:privacyPolicyUrl] = privacy_policy_url if privacy_policy_url
      attributes[:privacyChoicesUrl] = privacy_choices_url if privacy_choices_url
      attributes[:privacyPolicyText] = privacy_policy_text if privacy_policy_text

      return nil if attributes.empty?

      patch("/appInfoLocalizations/#{localization_id}", body: {
              data: {
                type: 'appInfoLocalizations',
                id: localization_id,
                attributes: attributes
              }
            })
    end

    # Get primary category for an app info
    def app_categories(app_info_id:)
      result = get("/appInfos/#{app_info_id}?include=primaryCategory,secondaryCategory")

      included = result['included'] || []
      categories = {}

      primary_id = result['data'].dig('relationships', 'primaryCategory', 'data', 'id')
      if primary_id
        primary = included.find { |i| i['id'] == primary_id }
        categories[:primary] = { id: primary_id, platforms: primary&.dig('attributes', 'platforms') } if primary
      end

      secondary_id = result['data'].dig('relationships', 'secondaryCategory', 'data', 'id')
      if secondary_id
        secondary = included.find { |i| i['id'] == secondary_id }
        categories[:secondary] = { id: secondary_id, platforms: secondary&.dig('attributes', 'platforms') } if secondary
      end

      categories
    end

    # List all available app categories
    def available_categories(platform: 'IOS')
      get("/appCategories?filter[platforms]=#{platform}")['data'].map do |cat|
        {
          id: cat['id'],
          platforms: cat.dig('attributes', 'platforms')
        }
      end
    end

    # Get age rating declaration
    def age_rating_declaration(app_info_id:)
      result = get("/appInfos/#{app_info_id}/ageRatingDeclaration")['data']
      return nil unless result

      {
        id: result['id'],
        alcohol_tobacco_or_drug_use_or_references: result.dig('attributes', 'alcoholTobaccoOrDrugUseOrReferences'),
        gambling: result.dig('attributes', 'gambling'),
        gambling_simulated: result.dig('attributes', 'gamblingSimulated'),
        violence_cartoon_or_fantasy: result.dig('attributes', 'violenceCartoonOrFantasy'),
        violence_realistic: result.dig('attributes', 'violenceRealistic'),
        seventeen_plus: result.dig('attributes', 'seventeenPlus')
      }
    rescue ApiError => e
      return nil if e.message.include?('Not found')

      raise
    end

    # ─────────────────────────────────────────────────────────────────────────
    # Low-level HTTP methods
    # ─────────────────────────────────────────────────────────────────────────

    def get(path, params: {})
      request(:get, path, params: params)
    end

    def post(path, body: {})
      request(:post, path, body: body)
    end

    def patch(path, body: {})
      request(:patch, path, body: body)
    end

    def delete(path)
      request(:delete, path)
    end

    def delete_with_body(path, body: {})
      request(:delete, path, body: body)
    end

    # Resolution Center methods (uses IRIS API)
    # Get resolution center threads for a review submission
    def resolution_center_threads(submission_id:)
      iris_get("/resolutionCenterThreads?filter[reviewSubmission]=#{submission_id}")
    rescue ApiError => e
      # IRIS API may not be accessible with standard JWT auth
      raise ApiError, "Resolution Center API error: #{e.message}. " \
                      'Note: Detailed rejection messages may require App Store Connect web UI access.'
    end

    # Get messages from a resolution center thread
    def resolution_center_messages(thread_id:)
      iris_get("/resolutionCenterThreads/#{thread_id}/resolutionCenterMessages")
    rescue ApiError => e
      raise ApiError, "Resolution Center messages error: #{e.message}"
    end

    # Get rejection messages for a thread
    def rejection_reasons(thread_id:)
      result = resolution_center_messages(thread_id: thread_id)
      messages = result['data'] || []

      messages.map do |msg|
        {
          id: msg['id'],
          body: msg.dig('attributes', 'messageBody'),
          created_date: msg.dig('attributes', 'createdDate')
        }
      end
    end

    private

    # Make request to IRIS API (Apple's internal API for resolution center)
    # Uses session cookies if available, falls back to JWT auth
    def iris_get(path)
      uri = URI("#{IRIS_URL}#{path}")

      headers = {
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
      }

      # Use session cookies if available (required for Resolution Center)
      if @session&.valid?
        headers['Cookie'] = @session.cookie_header
      else
        # Fall back to JWT auth (may not work for all IRIS endpoints)
        headers['Authorization'] = "Bearer #{generate_token}"
      end

      response = @http_client.execute(
        method: :get,
        url: uri.to_s,
        headers: headers,
        body: nil
      )

      result = response[:body]
      status_code = response[:status]

      # Provide helpful error message if session auth is needed
      if [401, 403].include?(status_code) && !@session&.valid?
        raise ApiError, 'Resolution Center requires session authentication. ' \
                        "Run 'fastlane spaceauth -u YOUR_APPLE_ID' and set FASTLANE_SESSION environment variable."
      end

      handle_error_response(result, status_code, path) if status_code >= 400

      result
    end

    def request(method, path, params: {}, body: nil)
      uri = URI("#{BASE_URL}#{path}")
      uri.query = URI.encode_www_form(params) if params.any?

      headers = {
        'Authorization' => "Bearer #{generate_token}",
        'Content-Type' => 'application/json'
      }

      response = @http_client.execute(
        method: method,
        url: uri.to_s,
        headers: headers,
        body: body
      )

      result = response[:body]
      status_code = response[:status]

      handle_error_response(result, status_code, path) if status_code >= 400

      if result.is_a?(Hash) && result['errors'].is_a?(Array) && result['errors'].any?
        error = result['errors'].first
        error_status = error['status']&.to_i || status_code
        handle_error_response(result, error_status, path)
      end

      result
    end

    def handle_error_response(result, status_code, path)
      detail = if result.is_a?(Hash) && result['errors'].is_a?(Array) && result['errors'].any?
                 error = result['errors'].first
                 error['detail'] || error['title'] || 'Unknown error'
               else
                 "HTTP #{status_code}"
               end

      case status_code
      when 401
        raise ApiError, 'Unauthorized - check your API key credentials'
      when 403
        raise ApiError, 'Forbidden - your API key may not have the required permissions'
      when 404
        raise ApiError, "Not found - resource doesn't exist: #{path}"
      when 429
        raise ApiError, 'Rate limited - too many requests'
      else
        raise ApiError, "API error (#{status_code}): #{detail}"
      end
    end

    def generate_token
      private_key = OpenSSL::PKey::EC.new(File.read(@private_key_path))

      header = {
        alg: 'ES256',
        kid: @key_id,
        typ: 'JWT'
      }

      now = Time.now.to_i
      payload = {
        iss: @issuer_id,
        iat: now,
        exp: now + (20 * 60),
        aud: 'appstoreconnect-v1'
      }

      JWT.encode(payload, private_key, 'ES256', header)
    end

    def validate_configuration!
      missing = []
      missing << 'APP_STORE_CONNECT_KEY_ID' if blank?(@key_id)
      missing << 'APP_STORE_CONNECT_ISSUER_ID' if blank?(@issuer_id)
      missing << 'APP_STORE_CONNECT_PRIVATE_KEY_PATH' if blank?(@private_key_path)

      raise ConfigurationError, "Missing configuration: #{missing.join(', ')}" if missing.any?

      raise ConfigurationError, "Private key file not found: #{@private_key_path}" unless File.exist?(@private_key_path)

      return if File.readable?(@private_key_path)

      raise ConfigurationError, "Private key file not readable: #{@private_key_path}"
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end

    def build_http_client(skip_crl_verification:, verify_ssl:, use_curl:)
      if use_curl
        CurlHttpClient.new(verify_ssl: verify_ssl)
      else
        HttpClient.new(
          skip_crl_verification: skip_crl_verification,
          verify_ssl: verify_ssl
        )
      end
    end
  end
end
