# frozen_string_literal: true

require "jwt"
require "json"
require "shellwords"
require "uri"
require "openssl"
require "time"

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
    BASE_URL = "https://api.appstoreconnect.apple.com/v1"

    def initialize(
      key_id: nil,
      issuer_id: nil,
      private_key_path: nil,
      app_id: nil,
      bundle_id: nil
    )
      config = AppStoreConnect.configuration

      @key_id = key_id || config.key_id
      @issuer_id = issuer_id || config.issuer_id
      @private_key_path = private_key_path || config.private_key_path
      @app_id = app_id || config.app_id
      @bundle_id = bundle_id || config.bundle_id

      validate_configuration!
    end

    attr_reader :app_id, :bundle_id

    # ─────────────────────────────────────────────────────────────────────────
    # High-level convenience methods
    # ─────────────────────────────────────────────────────────────────────────

    # Get a complete status summary for the configured app
    def app_status
      app = get("/apps/#{@app_id}")["data"]
      versions = app_store_versions
      reviews = review_submissions
      subs = subscriptions

      {
        app: {
          id: app["id"],
          name: app.dig("attributes", "name"),
          bundle_id: app.dig("attributes", "bundleId"),
          sku: app.dig("attributes", "sku")
        },
        versions: versions.map do |v|
          {
            version: v.dig("attributes", "versionString"),
            state: v.dig("attributes", "appStoreState"),
            release_type: v.dig("attributes", "releaseType"),
            created: v.dig("attributes", "createdDate")
          }
        end,
        latest_review: reviews.first&.then do |r|
          {
            state: r.dig("attributes", "state"),
            platform: r.dig("attributes", "platform"),
            submitted: r.dig("attributes", "submittedDate")
          }
        end,
        subscriptions: subs.map do |s|
          {
            product_id: s.dig("attributes", "productId"),
            name: s.dig("attributes", "name"),
            state: s.dig("attributes", "state"),
            group_level: s.dig("attributes", "groupLevel")
          }
        end
      }
    end

    # Check if app is ready for submission or has issues
    def submission_readiness
      status = app_status
      issues = []

      # Check version state
      preparing = status[:versions].find { |v| v[:state] == "PREPARE_FOR_SUBMISSION" }
      waiting = status[:versions].find { |v| v[:state] == "WAITING_FOR_REVIEW" }
      rejected = status[:versions].find { |v| v[:state] == "REJECTED" }

      if rejected
        issues << "Version #{rejected[:version]} was REJECTED - check App Store Connect for details"
      end

      # Check subscription states
      sub_issues = status[:subscriptions].select { |s| s[:state] == "MISSING_METADATA" }
      if sub_issues.any?
        issues << "Subscriptions missing metadata: #{sub_issues.map { |s| s[:product_id] }.join(', ')}"
      end

      sub_rejected = status[:subscriptions].select { |s| s[:state] == "REJECTED" }
      if sub_rejected.any?
        issues << "Subscriptions rejected: #{sub_rejected.map { |s| s[:product_id] }.join(', ')}"
      end

      {
        ready: issues.empty?,
        current_state: waiting ? "WAITING_FOR_REVIEW" : (preparing ? "PREPARE_FOR_SUBMISSION" : "UNKNOWN"),
        issues: issues,
        status: status
      }
    end

    # ─────────────────────────────────────────────────────────────────────────
    # API resource methods
    # ─────────────────────────────────────────────────────────────────────────

    def apps
      get("/apps")["data"].map do |app|
        {
          id: app["id"],
          name: app.dig("attributes", "name"),
          bundle_id: app.dig("attributes", "bundleId"),
          sku: app.dig("attributes", "sku")
        }
      end
    end

    def app_store_versions(target_app_id: nil)
      target_app_id ||= @app_id
      get("/apps/#{target_app_id}/appStoreVersions")["data"]
    end

    def review_submissions(target_app_id: nil, limit: 10)
      target_app_id ||= @app_id
      get("/apps/#{target_app_id}/reviewSubmissions?limit=#{limit}")["data"]
    end

    def subscription_groups(target_app_id: nil)
      target_app_id ||= @app_id
      get("/apps/#{target_app_id}/subscriptionGroups")["data"]
    end

    def subscriptions(target_app_id: nil)
      target_app_id ||= @app_id
      groups = subscription_groups(target_app_id: target_app_id)
      groups.flat_map do |group|
        group_id = group["id"]
        get("/subscriptionGroups/#{group_id}/subscriptions")["data"]
      end
    end

    def builds(target_app_id: nil, limit: 10)
      target_app_id ||= @app_id
      get("/apps/#{target_app_id}/builds?limit=#{limit}")["data"].map do |build|
        {
          id: build["id"],
          version: build.dig("attributes", "version"),
          uploaded: build.dig("attributes", "uploadedDate"),
          processing_state: build.dig("attributes", "processingState"),
          build_audience_type: build.dig("attributes", "buildAudienceType")
        }
      end
    end

    def beta_app_review_detail(target_app_id: nil)
      target_app_id ||= @app_id
      result = get("/apps/#{target_app_id}/betaAppReviewDetail")["data"]
      {
        id: result["id"],
        contact_first_name: result.dig("attributes", "contactFirstName"),
        contact_last_name: result.dig("attributes", "contactLastName"),
        contact_phone: result.dig("attributes", "contactPhone"),
        contact_email: result.dig("attributes", "contactEmail"),
        demo_account_name: result.dig("attributes", "demoAccountName"),
        demo_account_password: result.dig("attributes", "demoAccountPassword"),
        demo_account_required: result.dig("attributes", "demoAccountRequired"),
        notes: result.dig("attributes", "notes")
      }
    end

    def in_app_purchases(target_app_id: nil)
      target_app_id ||= @app_id
      get("/apps/#{target_app_id}/inAppPurchasesV2")["data"].map do |iap|
        {
          id: iap["id"],
          product_id: iap.dig("attributes", "productId"),
          name: iap.dig("attributes", "name"),
          state: iap.dig("attributes", "state"),
          type: iap.dig("attributes", "inAppPurchaseType")
        }
      end
    end

    # ─────────────────────────────────────────────────────────────────────────
    # Update methods (for responding to Apple Review requests)
    # ─────────────────────────────────────────────────────────────────────────

    # Update subscription metadata (name, group level)
    def update_subscription(subscription_id:, name: nil, group_level: nil)
      attributes = {}
      attributes[:name] = name if name
      attributes[:groupLevel] = group_level if group_level

      return nil if attributes.empty?

      patch("/subscriptions/#{subscription_id}", body: {
        data: {
          type: "subscriptions",
          id: subscription_id,
          attributes: attributes
        }
      })
    end

    # Get subscription localizations (display name, description shown to users)
    def subscription_localizations(subscription_id:)
      get("/subscriptions/#{subscription_id}/subscriptionLocalizations")["data"].map do |loc|
        {
          id: loc["id"],
          locale: loc.dig("attributes", "locale"),
          name: loc.dig("attributes", "name"),
          description: loc.dig("attributes", "description"),
          state: loc.dig("attributes", "state")
        }
      end
    end

    # Update subscription localization (display name/description users see)
    def update_subscription_localization(localization_id:, name: nil, description: nil)
      attributes = {}
      attributes[:name] = name if name
      attributes[:description] = description if description

      return nil if attributes.empty?

      patch("/subscriptionLocalizations/#{localization_id}", body: {
        data: {
          type: "subscriptionLocalizations",
          id: localization_id,
          attributes: attributes
        }
      })
    end

    # Create a new subscription localization
    def create_subscription_localization(subscription_id:, locale:, name:, description: nil)
      attributes = {
        locale: locale,
        name: name
      }
      attributes[:description] = description if description

      post("/subscriptionLocalizations", body: {
        data: {
          type: "subscriptionLocalizations",
          attributes: attributes,
          relationships: {
            subscription: {
              data: {
                type: "subscriptions",
                id: subscription_id
              }
            }
          }
        }
      })
    end

    # Get subscription price points for a territory
    def subscription_price_points(subscription_id:, territory: "USA")
      get("/subscriptions/#{subscription_id}/pricePoints?filter[territory]=#{territory}&include=territory")["data"]
    end

    # Get current subscription prices
    def subscription_prices(subscription_id:)
      get("/subscriptions/#{subscription_id}/prices?include=subscriptionPricePoint")["data"].map do |price|
        {
          id: price["id"],
          start_date: price.dig("attributes", "startDate"),
          preserved: price.dig("attributes", "preserved"),
          price_point_id: price.dig("relationships", "subscriptionPricePoint", "data", "id")
        }
      end
    end

    # Get app store version localizations (app description, what's new, keywords)
    def app_store_version_localizations(version_id:)
      get("/appStoreVersions/#{version_id}/appStoreVersionLocalizations")["data"].map do |loc|
        {
          id: loc["id"],
          locale: loc.dig("attributes", "locale"),
          description: loc.dig("attributes", "description"),
          keywords: loc.dig("attributes", "keywords"),
          whats_new: loc.dig("attributes", "whatsNew"),
          promotional_text: loc.dig("attributes", "promotionalText"),
          marketing_url: loc.dig("attributes", "marketingUrl"),
          support_url: loc.dig("attributes", "supportUrl")
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
          type: "appStoreVersionLocalizations",
          id: localization_id,
          attributes: attributes
        }
      })
    end

    # Get app info (category, age rating, etc.)
    def app_infos(target_app_id: nil)
      target_app_id ||= @app_id
      get("/apps/#{target_app_id}/appInfos")["data"]
    end

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
          type: "betaAppReviewDetails",
          id: detail_id,
          attributes: attributes
        }
      })
    end

    # Get app store review detail for a version
    def app_store_review_detail(version_id:)
      result = get("/appStoreVersions/#{version_id}/appStoreReviewDetail")["data"]
      return nil unless result

      {
        id: result["id"],
        contact_first_name: result.dig("attributes", "contactFirstName"),
        contact_last_name: result.dig("attributes", "contactLastName"),
        contact_phone: result.dig("attributes", "contactPhone"),
        contact_email: result.dig("attributes", "contactEmail"),
        demo_account_name: result.dig("attributes", "demoAccountName"),
        demo_account_password: result.dig("attributes", "demoAccountPassword"),
        demo_account_required: result.dig("attributes", "demoAccountRequired"),
        notes: result.dig("attributes", "notes")
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
          type: "appStoreReviewDetails",
          id: detail_id,
          attributes: attributes
        }
      })
    end

    # Submit a version for review
    def create_review_submission(platform: "IOS", target_app_id: nil)
      target_app_id ||= @app_id
      post("/reviewSubmissions", body: {
        data: {
          type: "reviewSubmissions",
          attributes: {
            platform: platform
          },
          relationships: {
            app: {
              data: {
                type: "apps",
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
          type: "reviewSubmissions",
          id: submission_id,
          attributes: {
            canceled: true
          }
        }
      })
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

    private

    def request(method, path, params: {}, body: nil)
      uri = URI("#{BASE_URL}#{path}")
      uri.query = URI.encode_www_form(params) if params.any?

      # Use curl to avoid Ruby's SSL CRL verification issues
      curl_method = method.to_s.upcase
      curl_cmd = [
        "curl", "-s", "-X", curl_method,
        "-H", "Authorization: Bearer #{generate_token}",
        "-H", "Content-Type: application/json"
      ]

      curl_cmd += ["-d", body.to_json] if body

      curl_cmd << uri.to_s

      output = `#{curl_cmd.shelljoin}`
      status = $?

      unless status.success?
        raise ApiError, "HTTP request failed with exit code #{status.exitstatus}"
      end

      begin
        result = JSON.parse(output)
      rescue JSON::ParserError => e
        raise ApiError, "Invalid JSON response: #{e.message}"
      end

      # Check for API errors in the response
      if result["errors"].is_a?(Array) && result["errors"].any?
        error = result["errors"].first
        status_code = error["status"]&.to_i || 500
        detail = error["detail"] || error["title"] || "Unknown error"

        case status_code
        when 401
          raise ApiError, "Unauthorized - check your API key credentials"
        when 403
          raise ApiError, "Forbidden - your API key may not have the required permissions"
        when 404
          raise ApiError, "Not found - resource doesn't exist: #{path}"
        when 429
          raise ApiError, "Rate limited - too many requests"
        else
          raise ApiError, "API error (#{status_code}): #{detail}"
        end
      end

      result
    end

    def generate_token
      private_key = OpenSSL::PKey::EC.new(File.read(@private_key_path))

      header = {
        alg: "ES256",
        kid: @key_id,
        typ: "JWT"
      }

      now = Time.now.to_i
      payload = {
        iss: @issuer_id,
        iat: now,
        exp: now + 20 * 60, # 20 minutes
        aud: "appstoreconnect-v1"
      }

      JWT.encode(payload, private_key, "ES256", header)
    end

    def validate_configuration!
      missing = []
      missing << "APP_STORE_CONNECT_KEY_ID" if blank?(@key_id)
      missing << "APP_STORE_CONNECT_ISSUER_ID" if blank?(@issuer_id)
      missing << "APP_STORE_CONNECT_PRIVATE_KEY_PATH" if blank?(@private_key_path)

      if missing.any?
        raise ConfigurationError, "Missing configuration: #{missing.join(', ')}"
      end

      unless File.exist?(@private_key_path)
        raise ConfigurationError, "Private key file not found: #{@private_key_path}"
      end

      unless File.readable?(@private_key_path)
        raise ConfigurationError, "Private key file not readable: #{@private_key_path}"
      end
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end
  end
end
