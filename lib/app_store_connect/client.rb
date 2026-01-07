# frozen_string_literal: true

require 'English'
require 'jwt'
require 'json'
require 'shellwords'
require 'uri'
require 'openssl'
require 'time'
require 'digest'
require 'base64'
require 'tempfile'

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
      app = get("/apps/#{@app_id}")['data']
      versions = app_store_versions
      reviews = review_submissions
      subs = subscriptions

      {
        app: {
          id: app['id'],
          name: app.dig('attributes', 'name'),
          bundle_id: app.dig('attributes', 'bundleId'),
          sku: app.dig('attributes', 'sku')
        },
        versions: versions.map do |v|
          {
            version: v.dig('attributes', 'versionString'),
            state: v.dig('attributes', 'appStoreState'),
            release_type: v.dig('attributes', 'releaseType'),
            created: v.dig('attributes', 'createdDate')
          }
        end,
        latest_review: reviews.first&.then do |r|
          {
            state: r.dig('attributes', 'state'),
            platform: r.dig('attributes', 'platform'),
            submitted: r.dig('attributes', 'submittedDate')
          }
        end,
        subscriptions: subs.map do |s|
          {
            product_id: s.dig('attributes', 'productId'),
            name: s.dig('attributes', 'name'),
            state: s.dig('attributes', 'state'),
            group_level: s.dig('attributes', 'groupLevel')
          }
        end
      }
    end

    # Check if app is ready for submission or has issues
    def submission_readiness
      status = app_status
      issues = []

      # Check version state
      preparing = status[:versions].find { |v| v[:state] == 'PREPARE_FOR_SUBMISSION' }
      waiting = status[:versions].find { |v| v[:state] == 'WAITING_FOR_REVIEW' }
      rejected = status[:versions].find { |v| v[:state] == 'REJECTED' }

      issues << "Version #{rejected[:version]} was REJECTED - check App Store Connect for details" if rejected

      # Check subscription states
      sub_issues = status[:subscriptions].select { |s| s[:state] == 'MISSING_METADATA' }
      issues << "Subscriptions missing metadata: #{sub_issues.map { |s| s[:product_id] }.join(', ')}" if sub_issues.any?

      sub_rejected = status[:subscriptions].select { |s| s[:state] == 'REJECTED' }
      issues << "Subscriptions rejected: #{sub_rejected.map { |s| s[:product_id] }.join(', ')}" if sub_rejected.any?

      {
        ready: issues.empty?,
        current_state: if waiting
                         'WAITING_FOR_REVIEW'
                       else
                         (preparing ? 'PREPARE_FOR_SUBMISSION' : 'UNKNOWN')
                       end,
        issues: issues,
        status: status
      }
    end

    # ─────────────────────────────────────────────────────────────────────────
    # API resource methods
    # ─────────────────────────────────────────────────────────────────────────

    def apps
      get('/apps')['data'].map do |app|
        {
          id: app['id'],
          name: app.dig('attributes', 'name'),
          bundle_id: app.dig('attributes', 'bundleId'),
          sku: app.dig('attributes', 'sku')
        }
      end
    end

    def app_store_versions(target_app_id: nil)
      target_app_id ||= @app_id
      get("/apps/#{target_app_id}/appStoreVersions")['data']
    end

    def review_submissions(target_app_id: nil, limit: 10)
      target_app_id ||= @app_id
      get("/apps/#{target_app_id}/reviewSubmissions?limit=#{limit}")['data']
    end

    def subscription_groups(target_app_id: nil)
      target_app_id ||= @app_id
      get("/apps/#{target_app_id}/subscriptionGroups")['data']
    end

    def subscriptions(target_app_id: nil)
      target_app_id ||= @app_id
      groups = subscription_groups(target_app_id: target_app_id)
      groups.flat_map do |group|
        group_id = group['id']
        get("/subscriptionGroups/#{group_id}/subscriptions")['data']
      end
    end

    def builds(target_app_id: nil, limit: 10)
      target_app_id ||= @app_id
      get("/apps/#{target_app_id}/builds?limit=#{limit}")['data'].map do |build|
        {
          id: build['id'],
          version: build.dig('attributes', 'version'),
          uploaded: build.dig('attributes', 'uploadedDate'),
          processing_state: build.dig('attributes', 'processingState'),
          build_audience_type: build.dig('attributes', 'buildAudienceType')
        }
      end
    end

    def beta_app_review_detail(target_app_id: nil)
      target_app_id ||= @app_id
      result = get("/apps/#{target_app_id}/betaAppReviewDetail")['data']
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
    end

    def in_app_purchases(target_app_id: nil)
      target_app_id ||= @app_id
      get("/apps/#{target_app_id}/inAppPurchasesV2")['data'].map do |iap|
        {
          id: iap['id'],
          product_id: iap.dig('attributes', 'productId'),
          name: iap.dig('attributes', 'name'),
          state: iap.dig('attributes', 'state'),
          type: iap.dig('attributes', 'inAppPurchaseType'),
          review_note: iap.dig('attributes', 'reviewNote')
        }
      end
    end

    # Get a single in-app purchase by ID
    def in_app_purchase(iap_id:)
      iap = get("/inAppPurchasesV2/#{iap_id}")['data']
      {
        id: iap['id'],
        product_id: iap.dig('attributes', 'productId'),
        name: iap.dig('attributes', 'name'),
        state: iap.dig('attributes', 'state'),
        type: iap.dig('attributes', 'inAppPurchaseType'),
        review_note: iap.dig('attributes', 'reviewNote')
      }
    end

    # Get in-app purchase localizations
    def in_app_purchase_localizations(iap_id:)
      get("/inAppPurchasesV2/#{iap_id}/inAppPurchaseLocalizations")['data'].map do |loc|
        {
          id: loc['id'],
          locale: loc.dig('attributes', 'locale'),
          name: loc.dig('attributes', 'name'),
          description: loc.dig('attributes', 'description'),
          state: loc.dig('attributes', 'state')
        }
      end
    end

    # Get customer reviews for the app
    def customer_reviews(target_app_id: nil, limit: 20, sort: '-createdDate')
      target_app_id ||= @app_id
      get("/apps/#{target_app_id}/customerReviews?limit=#{limit}&sort=#{sort}")['data'].map do |review|
        {
          id: review['id'],
          rating: review.dig('attributes', 'rating'),
          title: review.dig('attributes', 'title'),
          body: review.dig('attributes', 'body'),
          reviewer_nickname: review.dig('attributes', 'reviewerNickname'),
          created_date: review.dig('attributes', 'createdDate'),
          territory: review.dig('attributes', 'territory')
        }
      end
    end

    # Get the response to a customer review
    def customer_review_response(review_id:)
      result = get("/customerReviews/#{review_id}/response")['data']
      return nil unless result

      {
        id: result['id'],
        response_body: result.dig('attributes', 'responseBody'),
        last_modified_date: result.dig('attributes', 'lastModifiedDate'),
        state: result.dig('attributes', 'state')
      }
    rescue ApiError => e
      return nil if e.message.include?('Not found')

      raise
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
                type: 'subscriptions',
                id: subscription_id,
                attributes: attributes
              }
            })
    end

    # Get subscription localizations (display name, description shown to users)
    def subscription_localizations(subscription_id:)
      get("/subscriptions/#{subscription_id}/subscriptionLocalizations")['data'].map do |loc|
        {
          id: loc['id'],
          locale: loc.dig('attributes', 'locale'),
          name: loc.dig('attributes', 'name'),
          description: loc.dig('attributes', 'description'),
          state: loc.dig('attributes', 'state')
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
                type: 'subscriptionLocalizations',
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

      post('/subscriptionLocalizations', body: {
             data: {
               type: 'subscriptionLocalizations',
               attributes: attributes,
               relationships: {
                 subscription: {
                   data: {
                     type: 'subscriptions',
                     id: subscription_id
                   }
                 }
               }
             }
           })
    end

    # ─────────────────────────────────────────────────────────────────────────
    # In-App Purchase management (for responding to Apple Review requests)
    # ─────────────────────────────────────────────────────────────────────────

    # Update in-app purchase metadata (name, review note)
    def update_in_app_purchase(iap_id:, name: nil, review_note: nil)
      attributes = {}
      attributes[:name] = name if name
      attributes[:reviewNote] = review_note if review_note

      return nil if attributes.empty?

      patch("/inAppPurchasesV2/#{iap_id}", body: {
              data: {
                type: 'inAppPurchases',
                id: iap_id,
                attributes: attributes
              }
            })
    end

    # Create a new in-app purchase localization
    def create_in_app_purchase_localization(iap_id:, locale:, name:, description: nil)
      attributes = {
        locale: locale,
        name: name
      }
      attributes[:description] = description if description

      post('/inAppPurchaseLocalizations', body: {
             data: {
               type: 'inAppPurchaseLocalizations',
               attributes: attributes,
               relationships: {
                 inAppPurchaseV2: {
                   data: {
                     type: 'inAppPurchases',
                     id: iap_id
                   }
                 }
               }
             }
           })
    end

    # Update in-app purchase localization (display name/description users see)
    def update_in_app_purchase_localization(localization_id:, name: nil, description: nil)
      attributes = {}
      attributes[:name] = name if name
      attributes[:description] = description if description

      return nil if attributes.empty?

      patch("/inAppPurchaseLocalizations/#{localization_id}", body: {
              data: {
                type: 'inAppPurchaseLocalizations',
                id: localization_id,
                attributes: attributes
              }
            })
    end

    # Delete an in-app purchase localization
    def delete_in_app_purchase_localization(localization_id:)
      delete("/inAppPurchaseLocalizations/#{localization_id}")
    end

    # Submit in-app purchase for review
    def submit_in_app_purchase(iap_id:)
      post('/inAppPurchaseSubmissions', body: {
             data: {
               type: 'inAppPurchaseSubmissions',
               relationships: {
                 inAppPurchaseV2: {
                   data: {
                     type: 'inAppPurchases',
                     id: iap_id
                   }
                 }
               }
             }
           })
    end

    # ─────────────────────────────────────────────────────────────────────────
    # Customer Review responses
    # ─────────────────────────────────────────────────────────────────────────

    # Respond to a customer review
    def create_customer_review_response(review_id:, response_body:)
      post('/customerReviewResponses', body: {
             data: {
               type: 'customerReviewResponses',
               attributes: {
                 responseBody: response_body
               },
               relationships: {
                 review: {
                   data: {
                     type: 'customerReviews',
                     id: review_id
                   }
                 }
               }
             }
           })
    end

    # Delete a customer review response
    def delete_customer_review_response(response_id:)
      delete("/customerReviewResponses/#{response_id}")
    end

    # Get subscription price points for a territory
    def subscription_price_points(subscription_id:, territory: 'USA')
      get("/subscriptions/#{subscription_id}/pricePoints?filter[territory]=#{territory}&include=territory")['data']
    end

    # Get current subscription prices
    def subscription_prices(subscription_id:)
      get("/subscriptions/#{subscription_id}/prices?include=subscriptionPricePoint")['data'].map do |price|
        {
          id: price['id'],
          start_date: price.dig('attributes', 'startDate'),
          preserved: price.dig('attributes', 'preserved'),
          price_point_id: price.dig('relationships', 'subscriptionPricePoint', 'data', 'id')
        }
      end
    end

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

    # Get app info (category, age rating, etc.)
    def app_infos(target_app_id: nil)
      target_app_id ||= @app_id
      get("/apps/#{target_app_id}/appInfos")['data']
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
    # Asset Upload Methods (Screenshots, Previews, etc.)
    # ─────────────────────────────────────────────────────────────────────────

    # Upload an IAP review screenshot (for Apple reviewers, not shown to users)
    # Returns the created screenshot resource
    def upload_iap_review_screenshot(iap_id:, file_path:)
      raise ConfigurationError, "File not found: #{file_path}" unless File.exist?(file_path)

      file_name = File.basename(file_path)
      file_size = File.size(file_path)
      file_data = File.binread(file_path)

      # Step 1: Reserve the screenshot resource
      reservation = post('/inAppPurchaseAppStoreReviewScreenshots', body: {
                           data: {
                             type: 'inAppPurchaseAppStoreReviewScreenshots',
                             attributes: {
                               fileName: file_name,
                               fileSize: file_size
                             },
                             relationships: {
                               inAppPurchaseV2: {
                                 data: {
                                   type: 'inAppPurchases',
                                   id: iap_id
                                 }
                               }
                             }
                           }
                         })

      screenshot_id = reservation['data']['id']
      upload_operations = reservation['data']['attributes']['uploadOperations']

      # Step 2: Upload the file chunks
      upload_asset_chunks(file_data, upload_operations)

      # Step 3: Commit the upload
      checksum = Digest::MD5.base64digest(file_data)
      commit_asset_upload(
        path: "/inAppPurchaseAppStoreReviewScreenshots/#{screenshot_id}",
        type: 'inAppPurchaseAppStoreReviewScreenshots',
        id: screenshot_id,
        checksum: checksum
      )
    end

    # Get IAP review screenshot for an IAP
    def iap_review_screenshot(iap_id:)
      result = get("/inAppPurchasesV2/#{iap_id}/appStoreReviewScreenshot")['data']
      return nil unless result

      {
        id: result['id'],
        file_size: result.dig('attributes', 'fileSize'),
        file_name: result.dig('attributes', 'fileName'),
        asset_token: result.dig('attributes', 'assetToken'),
        image_asset: result.dig('attributes', 'imageAsset'),
        upload_state: result.dig('attributes', 'assetDeliveryState', 'state')
      }
    rescue ApiError => e
      return nil if e.message.include?('Not found')

      raise
    end

    # Delete an IAP review screenshot
    def delete_iap_review_screenshot(screenshot_id:)
      delete("/inAppPurchaseAppStoreReviewScreenshots/#{screenshot_id}")
    end

    # ─────────────────────────────────────────────────────────────────────────
    # App Store Screenshot Methods
    # ─────────────────────────────────────────────────────────────────────────

    # Get screenshot sets for a version localization
    def app_screenshot_sets(localization_id:)
      get("/appStoreVersionLocalizations/#{localization_id}/appScreenshotSets")['data'].map do |set|
        {
          id: set['id'],
          screenshot_display_type: set.dig('attributes', 'screenshotDisplayType')
        }
      end
    end

    # Get screenshots in a screenshot set
    def app_screenshots(screenshot_set_id:)
      get("/appScreenshotSets/#{screenshot_set_id}/appScreenshots")['data'].map do |screenshot|
        {
          id: screenshot['id'],
          file_size: screenshot.dig('attributes', 'fileSize'),
          file_name: screenshot.dig('attributes', 'fileName'),
          asset_token: screenshot.dig('attributes', 'assetToken'),
          image_asset: screenshot.dig('attributes', 'imageAsset'),
          upload_state: screenshot.dig('attributes', 'assetDeliveryState', 'state')
        }
      end
    end

    # Create a screenshot set for a specific display type
    def create_app_screenshot_set(localization_id:, display_type:)
      post('/appScreenshotSets', body: {
             data: {
               type: 'appScreenshotSets',
               attributes: {
                 screenshotDisplayType: display_type
               },
               relationships: {
                 appStoreVersionLocalization: {
                   data: {
                     type: 'appStoreVersionLocalizations',
                     id: localization_id
                   }
                 }
               }
             }
           })
    end

    # Upload an app screenshot
    # display_type examples: APP_IPHONE_67, APP_IPHONE_65, APP_IPAD_PRO_129, etc.
    def upload_app_screenshot(screenshot_set_id:, file_path:)
      raise ConfigurationError, "File not found: #{file_path}" unless File.exist?(file_path)

      file_name = File.basename(file_path)
      file_size = File.size(file_path)
      file_data = File.binread(file_path)

      # Step 1: Reserve the screenshot resource
      reservation = post('/appScreenshots', body: {
                           data: {
                             type: 'appScreenshots',
                             attributes: {
                               fileName: file_name,
                               fileSize: file_size
                             },
                             relationships: {
                               appScreenshotSet: {
                                 data: {
                                   type: 'appScreenshotSets',
                                   id: screenshot_set_id
                                 }
                               }
                             }
                           }
                         })

      screenshot_id = reservation['data']['id']
      upload_operations = reservation['data']['attributes']['uploadOperations']

      # Step 2: Upload the file chunks
      upload_asset_chunks(file_data, upload_operations)

      # Step 3: Commit the upload
      checksum = Digest::MD5.base64digest(file_data)
      commit_asset_upload(
        path: "/appScreenshots/#{screenshot_id}",
        type: 'appScreenshots',
        id: screenshot_id,
        checksum: checksum
      )
    end

    # Delete an app screenshot
    def delete_app_screenshot(screenshot_id:)
      delete("/appScreenshots/#{screenshot_id}")
    end

    # Reorder screenshots in a set
    def reorder_app_screenshots(screenshot_set_id:, screenshot_ids:)
      patch("/appScreenshotSets/#{screenshot_set_id}/relationships/appScreenshots", body: {
              data: screenshot_ids.map { |id| { type: 'appScreenshots', id: id } }
            })
    end

    # ─────────────────────────────────────────────────────────────────────────
    # App Preview Methods
    # ─────────────────────────────────────────────────────────────────────────

    # Get preview sets for a version localization
    def app_preview_sets(localization_id:)
      get("/appStoreVersionLocalizations/#{localization_id}/appPreviewSets")['data'].map do |set|
        {
          id: set['id'],
          preview_type: set.dig('attributes', 'previewType')
        }
      end
    end

    # Get previews in a preview set
    def app_previews(preview_set_id:)
      get("/appPreviewSets/#{preview_set_id}/appPreviews")['data'].map do |preview|
        {
          id: preview['id'],
          file_size: preview.dig('attributes', 'fileSize'),
          file_name: preview.dig('attributes', 'fileName'),
          preview_frame_time_code: preview.dig('attributes', 'previewFrameTimeCode'),
          video_url: preview.dig('attributes', 'videoUrl'),
          upload_state: preview.dig('attributes', 'assetDeliveryState', 'state')
        }
      end
    end

    # Create a preview set for a specific display type
    def create_app_preview_set(localization_id:, preview_type:)
      post('/appPreviewSets', body: {
             data: {
               type: 'appPreviewSets',
               attributes: {
                 previewType: preview_type
               },
               relationships: {
                 appStoreVersionLocalization: {
                   data: {
                     type: 'appStoreVersionLocalizations',
                     id: localization_id
                   }
                 }
               }
             }
           })
    end

    # Upload an app preview video
    def upload_app_preview(preview_set_id:, file_path:, preview_frame_time_code: nil)
      raise ConfigurationError, "File not found: #{file_path}" unless File.exist?(file_path)

      file_name = File.basename(file_path)
      file_size = File.size(file_path)
      file_data = File.binread(file_path)

      # Determine MIME type
      mime_type = case File.extname(file_path).downcase
                  when '.mov' then 'video/quicktime'
                  when '.m4v' then 'video/x-m4v'
                  when '.mp4' then 'video/mp4'
                  else 'video/quicktime'
                  end

      # Step 1: Reserve the preview resource
      attributes = {
        fileName: file_name,
        fileSize: file_size,
        mimeType: mime_type
      }
      attributes[:previewFrameTimeCode] = preview_frame_time_code if preview_frame_time_code

      reservation = post('/appPreviews', body: {
                           data: {
                             type: 'appPreviews',
                             attributes: attributes,
                             relationships: {
                               appPreviewSet: {
                                 data: {
                                   type: 'appPreviewSets',
                                   id: preview_set_id
                                 }
                               }
                             }
                           }
                         })

      preview_id = reservation['data']['id']
      upload_operations = reservation['data']['attributes']['uploadOperations']

      # Step 2: Upload the file chunks
      upload_asset_chunks(file_data, upload_operations)

      # Step 3: Commit the upload
      checksum = Digest::MD5.base64digest(file_data)
      commit_asset_upload(
        path: "/appPreviews/#{preview_id}",
        type: 'appPreviews',
        id: preview_id,
        checksum: checksum
      )
    end

    # Delete an app preview
    def delete_app_preview(preview_id:)
      delete("/appPreviews/#{preview_id}")
    end

    # ─────────────────────────────────────────────────────────────────────────
    # Release Automation Methods
    # ─────────────────────────────────────────────────────────────────────────

    # Create a new app store version
    # platform: IOS, MAC_OS, TV_OS, VISION_OS
    # release_type: MANUAL, AFTER_APPROVAL, SCHEDULED
    def create_app_store_version(version_string:, platform: 'IOS', release_type: 'AFTER_APPROVAL',
                                 earliest_release_date: nil, target_app_id: nil)
      target_app_id ||= @app_id

      attributes = {
        versionString: version_string,
        platform: platform,
        releaseType: release_type
      }

      # For SCHEDULED release type, set the earliest release date
      attributes[:earliestReleaseDate] = earliest_release_date if earliest_release_date && release_type == 'SCHEDULED'

      result = post('/appStoreVersions', body: {
                      data: {
                        type: 'appStoreVersions',
                        attributes: attributes,
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

      {
        id: result['data']['id'],
        version_string: result['data'].dig('attributes', 'versionString'),
        state: result['data'].dig('attributes', 'appStoreState'),
        release_type: result['data'].dig('attributes', 'releaseType'),
        created_date: result['data'].dig('attributes', 'createdDate')
      }
    end

    # Update app store version settings
    def update_app_store_version(version_id:, release_type: nil, earliest_release_date: nil,
                                 version_string: nil, downloadable: nil)
      attributes = {}
      attributes[:releaseType] = release_type if release_type
      attributes[:earliestReleaseDate] = earliest_release_date if earliest_release_date
      attributes[:versionString] = version_string if version_string
      attributes[:downloadable] = downloadable unless downloadable.nil?

      return nil if attributes.empty?

      patch("/appStoreVersions/#{version_id}", body: {
              data: {
                type: 'appStoreVersions',
                id: version_id,
                attributes: attributes
              }
            })
    end

    # Get phased release info for a version
    def phased_release(version_id:)
      result = get("/appStoreVersions/#{version_id}/appStoreVersionPhasedRelease")['data']
      return nil unless result

      {
        id: result['id'],
        state: result.dig('attributes', 'phasedReleaseState'),
        start_date: result.dig('attributes', 'startDate'),
        total_pause_duration: result.dig('attributes', 'totalPauseDuration'),
        current_day_number: result.dig('attributes', 'currentDayNumber')
      }
    rescue ApiError => e
      return nil if e.message.include?('Not found')

      raise
    end

    # Enable phased release for a version (7-day gradual rollout)
    # This creates a phased release that will start when the version is released
    def create_phased_release(version_id:)
      result = post('/appStoreVersionPhasedReleases', body: {
                      data: {
                        type: 'appStoreVersionPhasedReleases',
                        attributes: {
                          phasedReleaseState: 'INACTIVE'
                        },
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
        state: result['data'].dig('attributes', 'phasedReleaseState')
      }
    end

    # Update phased release state
    # state: INACTIVE, ACTIVE, PAUSED, COMPLETE
    # - INACTIVE: Phased release not yet started
    # - ACTIVE: Phased release in progress (auto-starts when version released)
    # - PAUSED: Phased release paused (existing users still get update)
    # - COMPLETE: Immediately release to all users
    def update_phased_release(phased_release_id:, state:)
      patch("/appStoreVersionPhasedReleases/#{phased_release_id}", body: {
              data: {
                type: 'appStoreVersionPhasedReleases',
                id: phased_release_id,
                attributes: {
                  phasedReleaseState: state
                }
              }
            })
    end

    # Delete phased release (disable gradual rollout)
    def delete_phased_release(phased_release_id:)
      delete("/appStoreVersionPhasedReleases/#{phased_release_id}")
    end

    # Release a version that's pending developer release
    # This is used when release_type is MANUAL and the version is approved
    def release_version(version_id:)
      # First check if version is in correct state
      versions = app_store_versions
      version = versions.find { |v| v['id'] == version_id }

      raise ApiError, "Version not found: #{version_id}" unless version

      state = version.dig('attributes', 'appStoreState')
      unless state == 'PENDING_DEVELOPER_RELEASE'
        raise ApiError, "Version must be PENDING_DEVELOPER_RELEASE to release (current: #{state})"
      end

      # Trigger release by updating releaseType to AFTER_APPROVAL
      # This tells Apple to release immediately
      patch("/appStoreVersions/#{version_id}", body: {
              data: {
                type: 'appStoreVersions',
                id: version_id,
                attributes: {
                  releaseType: 'AFTER_APPROVAL'
                }
              }
            })
    end

    # ─────────────────────────────────────────────────────────────────────────
    # Pre-Order Management
    # ─────────────────────────────────────────────────────────────────────────

    # Get pre-order info for an app
    def pre_order(target_app_id: nil)
      target_app_id ||= @app_id
      result = get("/apps/#{target_app_id}/preOrder")['data']
      return nil unless result

      {
        id: result['id'],
        pre_order_available_date: result.dig('attributes', 'preOrderAvailableDate'),
        app_release_date: result.dig('attributes', 'appReleaseDate')
      }
    rescue ApiError => e
      return nil if e.message.include?('Not found')

      raise
    end

    # Enable pre-order for an app
    # app_release_date: Date when the app will be released (format: "2024-12-25")
    def create_pre_order(app_release_date:, target_app_id: nil)
      target_app_id ||= @app_id

      result = post('/appPreOrders', body: {
                      data: {
                        type: 'appPreOrders',
                        attributes: {
                          appReleaseDate: app_release_date
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

      {
        id: result['data']['id'],
        app_release_date: result['data'].dig('attributes', 'appReleaseDate')
      }
    end

    # Update pre-order release date
    def update_pre_order(pre_order_id:, app_release_date:)
      patch("/appPreOrders/#{pre_order_id}", body: {
              data: {
                type: 'appPreOrders',
                id: pre_order_id,
                attributes: {
                  appReleaseDate: app_release_date
                }
              }
            })
    end

    # Delete pre-order (cancel pre-order availability)
    def delete_pre_order(pre_order_id:)
      delete("/appPreOrders/#{pre_order_id}")
    end

    # ─────────────────────────────────────────────────────────────────────────
    # TestFlight - Beta Testers
    # ─────────────────────────────────────────────────────────────────────────

    # List all beta testers for an app
    def beta_testers(target_app_id: nil, limit: 100)
      target_app_id ||= @app_id
      get("/betaTesters?filter[apps]=#{target_app_id}&limit=#{limit}")['data'].map do |tester|
        {
          id: tester['id'],
          email: tester.dig('attributes', 'email'),
          first_name: tester.dig('attributes', 'firstName'),
          last_name: tester.dig('attributes', 'lastName'),
          invite_type: tester.dig('attributes', 'inviteType'),
          state: tester.dig('attributes', 'state')
        }
      end
    end

    # Get a single beta tester by ID
    def beta_tester(tester_id:)
      tester = get("/betaTesters/#{tester_id}")['data']
      {
        id: tester['id'],
        email: tester.dig('attributes', 'email'),
        first_name: tester.dig('attributes', 'firstName'),
        last_name: tester.dig('attributes', 'lastName'),
        invite_type: tester.dig('attributes', 'inviteType'),
        state: tester.dig('attributes', 'state')
      }
    end

    # Invite a new beta tester
    def create_beta_tester(email:, first_name: nil, last_name: nil, group_ids: [], target_app_id: nil)
      target_app_id ||= @app_id

      attributes = { email: email }
      attributes[:firstName] = first_name if first_name
      attributes[:lastName] = last_name if last_name

      relationships = {}

      # Add to beta groups if specified
      if group_ids.any?
        relationships[:betaGroups] = {
          data: group_ids.map { |id| { type: 'betaGroups', id: id } }
        }
      else
        # If no groups specified, add to app directly
        relationships[:apps] = {
          data: [{ type: 'apps', id: target_app_id }]
        }
      end

      result = post('/betaTesters', body: {
                      data: {
                        type: 'betaTesters',
                        attributes: attributes,
                        relationships: relationships
                      }
                    })

      {
        id: result['data']['id'],
        email: result['data'].dig('attributes', 'email'),
        state: result['data'].dig('attributes', 'state')
      }
    end

    # Remove a beta tester from the app
    def delete_beta_tester(tester_id:)
      delete("/betaTesters/#{tester_id}")
    end

    # Add tester to beta groups
    def add_tester_to_groups(tester_id:, group_ids:)
      post("/betaTesters/#{tester_id}/relationships/betaGroups", body: {
             data: group_ids.map { |id| { type: 'betaGroups', id: id } }
           })
    end

    # Remove tester from beta groups
    def remove_tester_from_groups(tester_id:, group_ids:)
      delete_with_body("/betaTesters/#{tester_id}/relationships/betaGroups", body: {
                         data: group_ids.map { |id| { type: 'betaGroups', id: id } }
                       })
    end

    # ─────────────────────────────────────────────────────────────────────────
    # TestFlight - Beta Groups
    # ─────────────────────────────────────────────────────────────────────────

    # List all beta groups for an app
    def beta_groups(target_app_id: nil)
      target_app_id ||= @app_id
      get("/apps/#{target_app_id}/betaGroups")['data'].map do |group|
        {
          id: group['id'],
          name: group.dig('attributes', 'name'),
          is_internal: group.dig('attributes', 'isInternalGroup'),
          public_link_enabled: group.dig('attributes', 'publicLinkEnabled'),
          public_link: group.dig('attributes', 'publicLink'),
          public_link_limit: group.dig('attributes', 'publicLinkLimit'),
          public_link_limit_enabled: group.dig('attributes', 'publicLinkLimitEnabled'),
          created_date: group.dig('attributes', 'createdDate')
        }
      end
    end

    # Get a single beta group
    def beta_group(group_id:)
      group = get("/betaGroups/#{group_id}")['data']
      {
        id: group['id'],
        name: group.dig('attributes', 'name'),
        is_internal: group.dig('attributes', 'isInternalGroup'),
        public_link_enabled: group.dig('attributes', 'publicLinkEnabled'),
        public_link: group.dig('attributes', 'publicLink'),
        public_link_limit: group.dig('attributes', 'publicLinkLimit'),
        public_link_limit_enabled: group.dig('attributes', 'publicLinkLimitEnabled'),
        created_date: group.dig('attributes', 'createdDate')
      }
    end

    # Create a new beta group
    def create_beta_group(name:, public_link_enabled: false, public_link_limit: nil,
                          public_link_limit_enabled: false, feedback_enabled: true, target_app_id: nil)
      target_app_id ||= @app_id

      attributes = {
        name: name,
        publicLinkEnabled: public_link_enabled,
        publicLinkLimitEnabled: public_link_limit_enabled,
        feedbackEnabled: feedback_enabled
      }
      attributes[:publicLinkLimit] = public_link_limit if public_link_limit

      result = post('/betaGroups', body: {
                      data: {
                        type: 'betaGroups',
                        attributes: attributes,
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

      {
        id: result['data']['id'],
        name: result['data'].dig('attributes', 'name'),
        public_link: result['data'].dig('attributes', 'publicLink')
      }
    end

    # Update a beta group
    def update_beta_group(group_id:, name: nil, public_link_enabled: nil,
                          public_link_limit: nil, public_link_limit_enabled: nil, feedback_enabled: nil)
      attributes = {}
      attributes[:name] = name if name
      attributes[:publicLinkEnabled] = public_link_enabled unless public_link_enabled.nil?
      attributes[:publicLinkLimit] = public_link_limit if public_link_limit
      attributes[:publicLinkLimitEnabled] = public_link_limit_enabled unless public_link_limit_enabled.nil?
      attributes[:feedbackEnabled] = feedback_enabled unless feedback_enabled.nil?

      return nil if attributes.empty?

      patch("/betaGroups/#{group_id}", body: {
              data: {
                type: 'betaGroups',
                id: group_id,
                attributes: attributes
              }
            })
    end

    # Delete a beta group
    def delete_beta_group(group_id:)
      delete("/betaGroups/#{group_id}")
    end

    # Get testers in a beta group
    def beta_group_testers(group_id:, limit: 100)
      get("/betaGroups/#{group_id}/betaTesters?limit=#{limit}")['data'].map do |tester|
        {
          id: tester['id'],
          email: tester.dig('attributes', 'email'),
          first_name: tester.dig('attributes', 'firstName'),
          last_name: tester.dig('attributes', 'lastName'),
          state: tester.dig('attributes', 'state')
        }
      end
    end

    # Add testers to a beta group
    def add_testers_to_group(group_id:, tester_ids:)
      post("/betaGroups/#{group_id}/relationships/betaTesters", body: {
             data: tester_ids.map { |id| { type: 'betaTesters', id: id } }
           })
    end

    # Remove testers from a beta group
    def remove_testers_from_group(group_id:, tester_ids:)
      delete_with_body("/betaGroups/#{group_id}/relationships/betaTesters", body: {
                         data: tester_ids.map { |id| { type: 'betaTesters', id: id } }
                       })
    end

    # ─────────────────────────────────────────────────────────────────────────
    # TestFlight - Build Distribution
    # ─────────────────────────────────────────────────────────────────────────

    # Get builds available for TestFlight
    def testflight_builds(target_app_id: nil, limit: 20)
      target_app_id ||= @app_id
      get("/builds?filter[app]=#{target_app_id}&limit=#{limit}&sort=-uploadedDate")['data'].map do |build|
        {
          id: build['id'],
          version: build.dig('attributes', 'version'),
          uploaded_date: build.dig('attributes', 'uploadedDate'),
          processing_state: build.dig('attributes', 'processingState'),
          uses_non_exempt_encryption: build.dig('attributes', 'usesNonExemptEncryption'),
          expired: build.dig('attributes', 'expired')
        }
      end
    end

    # Get beta build details (TestFlight-specific info)
    def beta_build_detail(build_id:)
      result = get("/builds/#{build_id}/buildBetaDetail")['data']
      return nil unless result

      {
        id: result['id'],
        auto_notify_enabled: result.dig('attributes', 'autoNotifyEnabled'),
        internal_build_state: result.dig('attributes', 'internalBuildState'),
        external_build_state: result.dig('attributes', 'externalBuildState')
      }
    rescue ApiError => e
      return nil if e.message.include?('Not found')

      raise
    end

    # Update beta build details (enable/disable auto-notify)
    def update_beta_build_detail(beta_detail_id:, auto_notify_enabled:)
      patch("/buildBetaDetails/#{beta_detail_id}", body: {
              data: {
                type: 'buildBetaDetails',
                id: beta_detail_id,
                attributes: {
                  autoNotifyEnabled: auto_notify_enabled
                }
              }
            })
    end

    # Add build to beta groups (distribute to testers)
    def add_build_to_groups(build_id:, group_ids:)
      post("/builds/#{build_id}/relationships/betaGroups", body: {
             data: group_ids.map { |id| { type: 'betaGroups', id: id } }
           })
    end

    # Remove build from beta groups
    def remove_build_from_groups(build_id:, group_ids:)
      delete_with_body("/builds/#{build_id}/relationships/betaGroups", body: {
                         data: group_ids.map { |id| { type: 'betaGroups', id: id } }
                       })
    end

    # Get beta groups a build is distributed to
    def build_beta_groups(build_id:)
      get("/builds/#{build_id}/betaGroups")['data'].map do |group|
        {
          id: group['id'],
          name: group.dig('attributes', 'name'),
          is_internal: group.dig('attributes', 'isInternalGroup')
        }
      end
    end

    # ─────────────────────────────────────────────────────────────────────────
    # TestFlight - Beta Build Localizations (What's New)
    # ─────────────────────────────────────────────────────────────────────────

    # Get beta build localizations (What's New text for TestFlight)
    def beta_build_localizations(build_id:)
      get("/builds/#{build_id}/betaBuildLocalizations")['data'].map do |loc|
        {
          id: loc['id'],
          locale: loc.dig('attributes', 'locale'),
          whats_new: loc.dig('attributes', 'whatsNew')
        }
      end
    end

    # Create beta build localization
    def create_beta_build_localization(build_id:, locale:, whats_new:)
      result = post('/betaBuildLocalizations', body: {
                      data: {
                        type: 'betaBuildLocalizations',
                        attributes: {
                          locale: locale,
                          whatsNew: whats_new
                        },
                        relationships: {
                          build: {
                            data: {
                              type: 'builds',
                              id: build_id
                            }
                          }
                        }
                      }
                    })

      {
        id: result['data']['id'],
        locale: result['data'].dig('attributes', 'locale'),
        whats_new: result['data'].dig('attributes', 'whatsNew')
      }
    end

    # Update beta build localization
    def update_beta_build_localization(localization_id:, whats_new:)
      patch("/betaBuildLocalizations/#{localization_id}", body: {
              data: {
                type: 'betaBuildLocalizations',
                id: localization_id,
                attributes: {
                  whatsNew: whats_new
                }
              }
            })
    end

    # ─────────────────────────────────────────────────────────────────────────
    # TestFlight - Beta App Review Submission
    # ─────────────────────────────────────────────────────────────────────────

    # Submit a build for beta app review (required for external testers)
    def submit_for_beta_review(build_id:)
      post('/betaAppReviewSubmissions', body: {
             data: {
               type: 'betaAppReviewSubmissions',
               relationships: {
                 build: {
                   data: {
                     type: 'builds',
                     id: build_id
                   }
                 }
               }
             }
           })
    end

    # Get beta app review submission status
    def beta_app_review_submission(build_id:)
      result = get("/builds/#{build_id}/betaAppReviewSubmission")['data']
      return nil unless result

      {
        id: result['id'],
        beta_review_state: result.dig('attributes', 'betaReviewState'),
        submitted_date: result.dig('attributes', 'submittedDate')
      }
    rescue ApiError => e
      return nil if e.message.include?('Not found')

      raise
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
      result = get("/appInfos/#{app_info_id}?include=primaryCategory,secondaryCategory,primarySubcategoryOne,primarySubcategoryTwo,secondarySubcategoryOne,secondarySubcategoryTwo")

      included = result['included'] || []
      categories = {}

      # Extract primary category
      primary_id = result['data'].dig('relationships', 'primaryCategory', 'data', 'id')
      if primary_id
        primary = included.find { |i| i['id'] == primary_id }
        categories[:primary] = if primary&.dig('attributes', 'platforms')&.first
                                 {
                                   id: primary_id,
                                   name: primary.dig('attributes', 'platforms')
                                 }
                               end
      end

      # Extract secondary category
      secondary_id = result['data'].dig('relationships', 'secondaryCategory', 'data', 'id')
      if secondary_id
        secondary = included.find { |i| i['id'] == secondary_id }
        categories[:secondary] = if secondary
                                   {
                                     id: secondary_id,
                                     name: secondary.dig('attributes', 'platforms')
                                   }
                                 end
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

    # Update app categories
    def update_app_categories(app_info_id:, primary_category_id: nil, secondary_category_id: nil,
                              primary_subcategory_one_id: nil, primary_subcategory_two_id: nil,
                              secondary_subcategory_one_id: nil, secondary_subcategory_two_id: nil)
      relationships = {}

      if primary_category_id
        relationships[:primaryCategory] = {
          data: primary_category_id ? { type: 'appCategories', id: primary_category_id } : nil
        }
      end

      if secondary_category_id
        relationships[:secondaryCategory] = {
          data: secondary_category_id ? { type: 'appCategories', id: secondary_category_id } : nil
        }
      end

      if primary_subcategory_one_id
        relationships[:primarySubcategoryOne] = {
          data: { type: 'appCategories', id: primary_subcategory_one_id }
        }
      end

      if primary_subcategory_two_id
        relationships[:primarySubcategoryTwo] = {
          data: { type: 'appCategories', id: primary_subcategory_two_id }
        }
      end

      if secondary_subcategory_one_id
        relationships[:secondarySubcategoryOne] = {
          data: { type: 'appCategories', id: secondary_subcategory_one_id }
        }
      end

      if secondary_subcategory_two_id
        relationships[:secondarySubcategoryTwo] = {
          data: { type: 'appCategories', id: secondary_subcategory_two_id }
        }
      end

      return nil if relationships.empty?

      patch("/appInfos/#{app_info_id}", body: {
              data: {
                type: 'appInfos',
                id: app_info_id,
                relationships: relationships
              }
            })
    end

    # Get age rating declaration
    def age_rating_declaration(app_info_id:)
      result = get("/appInfos/#{app_info_id}/ageRatingDeclaration")['data']
      return nil unless result

      {
        id: result['id'],
        alcohol_tobacco_or_drug_use_or_references: result.dig('attributes', 'alcoholTobaccoOrDrugUseOrReferences'),
        contests: result.dig('attributes', 'contests'),
        gambling: result.dig('attributes', 'gambling'),
        gambling_simulated: result.dig('attributes', 'gamblingSimulated'),
        horror_or_fear_themes: result.dig('attributes', 'horrorOrFearThemes'),
        mature_or_suggestive_themes: result.dig('attributes', 'matureOrSuggestiveThemes'),
        medical_or_treatment_information: result.dig('attributes', 'medicalOrTreatmentInformation'),
        profanity_or_crude_humor: result.dig('attributes', 'profanityOrCrudeHumor'),
        sexual_content_graphic_and_nudity: result.dig('attributes', 'sexualContentGraphicAndNudity'),
        sexual_content_or_nudity: result.dig('attributes', 'sexualContentOrNudity'),
        violence_cartoon_or_fantasy: result.dig('attributes', 'violenceCartoonOrFantasy'),
        violence_realistic: result.dig('attributes', 'violenceRealistic'),
        violence_realistic_prolonged_graphic_or_sadistic: result.dig('attributes',
                                                                     'violenceRealisticProlongedGraphicOrSadistic'),
        seventeen_plus: result.dig('attributes', 'seventeenPlus'),
        kids_age_band: result.dig('attributes', 'kidsAgeBand'),
        unrestricted_web_access: result.dig('attributes', 'unrestrictedWebAccess')
      }
    rescue ApiError => e
      return nil if e.message.include?('Not found')

      raise
    end

    # Update age rating declaration
    # Values for most fields: NONE, INFREQUENT_OR_MILD, FREQUENT_OR_INTENSE
    # For gamblingSimulated: boolean
    # For seventeenPlus: boolean
    def update_age_rating_declaration(declaration_id:, **attributes)
      api_attributes = {}

      attribute_mapping = {
        alcohol_tobacco_or_drug_use_or_references: :alcoholTobaccoOrDrugUseOrReferences,
        contests: :contests,
        gambling: :gambling,
        gambling_simulated: :gamblingSimulated,
        horror_or_fear_themes: :horrorOrFearThemes,
        mature_or_suggestive_themes: :matureOrSuggestiveThemes,
        medical_or_treatment_information: :medicalOrTreatmentInformation,
        profanity_or_crude_humor: :profanityOrCrudeHumor,
        sexual_content_graphic_and_nudity: :sexualContentGraphicAndNudity,
        sexual_content_or_nudity: :sexualContentOrNudity,
        violence_cartoon_or_fantasy: :violenceCartoonOrFantasy,
        violence_realistic: :violenceRealistic,
        violence_realistic_prolonged_graphic_or_sadistic: :violenceRealisticProlongedGraphicOrSadistic,
        seventeen_plus: :seventeenPlus,
        kids_age_band: :kidsAgeBand,
        unrestricted_web_access: :unrestrictedWebAccess
      }

      attributes.each do |key, value|
        api_key = attribute_mapping[key]
        api_attributes[api_key] = value if api_key && !value.nil?
      end

      return nil if api_attributes.empty?

      patch("/ageRatingDeclarations/#{declaration_id}", body: {
              data: {
                type: 'ageRatingDeclarations',
                id: declaration_id,
                attributes: api_attributes
              }
            })
    end

    # ─────────────────────────────────────────────────────────────────────────
    # Pricing and Availability Methods
    # ─────────────────────────────────────────────────────────────────────────

    # Get app price schedule (current and future prices)
    def app_price_schedule(target_app_id: nil)
      target_app_id ||= @app_id
      result = get("/apps/#{target_app_id}/appPriceSchedule?include=manualPrices,automaticPrices,baseTerritory")

      schedule = result['data']
      included = result['included'] || []

      # Find base territory
      base_territory_id = schedule.dig('relationships', 'baseTerritory', 'data', 'id')
      base_territory = included.find { |i| i['type'] == 'territories' && i['id'] == base_territory_id }

      # Find manual prices
      manual_price_ids = schedule.dig('relationships', 'manualPrices', 'data')&.map { |p| p['id'] } || []
      manual_prices = included.select { |i| i['type'] == 'appPrices' && manual_price_ids.include?(i['id']) }

      {
        id: schedule['id'],
        base_territory: base_territory&.dig('attributes', 'currency'),
        manual_prices: manual_prices.map do |price|
          {
            id: price['id'],
            start_date: price.dig('attributes', 'startDate'),
            end_date: price.dig('attributes', 'endDate')
          }
        end
      }
    rescue ApiError => e
      return nil if e.message.include?('Not found')

      raise
    end

    # Get available price points for a territory
    def app_price_points(target_app_id: nil, territory: 'USA', limit: 50)
      target_app_id ||= @app_id
      get("/apps/#{target_app_id}/appPricePoints?filter[territory]=#{territory}&limit=#{limit}")['data'].map do |point|
        {
          id: point['id'],
          customer_price: point.dig('attributes', 'customerPrice'),
          proceeds: point.dig('attributes', 'proceeds')
        }
      end
    end

    # Get app availability (territories where app is available)
    def app_availability(target_app_id: nil)
      target_app_id ||= @app_id
      result = get("/apps/#{target_app_id}/appAvailability?include=availableTerritories")

      availability = result['data']
      included = result['included'] || []

      territories = included.select { |i| i['type'] == 'territories' }

      {
        id: availability['id'],
        available_in_new_territories: availability.dig('attributes', 'availableInNewTerritories'),
        territories: territories.map do |t|
          {
            id: t['id'],
            currency: t.dig('attributes', 'currency')
          }
        end
      }
    rescue ApiError => e
      return nil if e.message.include?('Not found')

      raise
    end

    # List all territories
    def territories(limit: 200)
      get("/territories?limit=#{limit}")['data'].map do |t|
        {
          id: t['id'],
          currency: t.dig('attributes', 'currency')
        }
      end
    end

    # Update app availability (set available_in_new_territories)
    def update_app_availability(availability_id:, available_in_new_territories:)
      patch("/appAvailabilities/#{availability_id}", body: {
              data: {
                type: 'appAvailabilities',
                id: availability_id,
                attributes: {
                  availableInNewTerritories: available_in_new_territories
                }
              }
            })
    end

    # ─────────────────────────────────────────────────────────────────────────
    # Sales and Finance Reports
    # ─────────────────────────────────────────────────────────────────────────

    # NOTE: Sales and Finance reports use a different API endpoint and format
    # They return gzipped TSV files, not JSON

    # Get sales report
    # frequency: DAILY, WEEKLY, MONTHLY, YEARLY
    # report_type: SALES, PRE_ORDER, NEWSSTAND, SUBSCRIPTION, SUBSCRIPTION_EVENT, SUBSCRIBER
    # report_sub_type: SUMMARY, DETAILED, OPT_IN
    def sales_report(vendor_number:, frequency: 'DAILY', report_type: 'SALES',
                     report_sub_type: 'SUMMARY', report_date: nil)
      params = {
        'filter[vendorNumber]' => vendor_number,
        'filter[frequency]' => frequency,
        'filter[reportType]' => report_type,
        'filter[reportSubType]' => report_sub_type
      }
      params['filter[reportDate]'] = report_date if report_date

      # Sales reports return gzipped data, need special handling
      uri = URI("#{BASE_URL}/salesReports")
      uri.query = URI.encode_www_form(params)

      curl_cmd = [
        'curl', '-s', '-X', 'GET',
        '-H', "Authorization: Bearer #{generate_token}",
        '-H', 'Accept: application/a]gzip'
      ]
      curl_cmd << uri.to_s

      output = `#{curl_cmd.shelljoin}`
      status = $CHILD_STATUS

      raise ApiError, 'Sales report request failed' unless status.success?

      # Try to parse as JSON error first
      begin
        result = JSON.parse(output)
        if result['errors']
          error = result['errors'].first
          raise ApiError, "Sales report error: #{error['detail'] || error['title']}"
        end
      rescue JSON::ParserError
        # Not JSON, likely gzipped data - return raw
      end

      output
    end

    # Get finance report
    def finance_report(vendor_number:, region_code:, report_type: 'FINANCIAL',
                       report_date: nil)
      params = {
        'filter[vendorNumber]' => vendor_number,
        'filter[regionCode]' => region_code,
        'filter[reportType]' => report_type
      }
      params['filter[reportDate]'] = report_date if report_date

      uri = URI("#{BASE_URL}/financeReports")
      uri.query = URI.encode_www_form(params)

      curl_cmd = [
        'curl', '-s', '-X', 'GET',
        '-H', "Authorization: Bearer #{generate_token}",
        '-H', 'Accept: application/a-gzip'
      ]
      curl_cmd << uri.to_s

      output = `#{curl_cmd.shelljoin}`
      status = $CHILD_STATUS

      raise ApiError, 'Finance report request failed' unless status.success?

      begin
        result = JSON.parse(output)
        if result['errors']
          error = result['errors'].first
          raise ApiError, "Finance report error: #{error['detail'] || error['title']}"
        end
      rescue JSON::ParserError
        # Not JSON, likely gzipped data
      end

      output
    end

    # ─────────────────────────────────────────────────────────────────────────
    # User Invitation Methods
    # ─────────────────────────────────────────────────────────────────────────

    # List all users in the team
    def users(limit: 100)
      get("/users?limit=#{limit}")['data'].map do |user|
        {
          id: user['id'],
          username: user.dig('attributes', 'username'),
          first_name: user.dig('attributes', 'firstName'),
          last_name: user.dig('attributes', 'lastName'),
          email: user.dig('attributes', 'email'),
          roles: user.dig('attributes', 'roles'),
          all_apps_visible: user.dig('attributes', 'allAppsVisible'),
          provisioning_allowed: user.dig('attributes', 'provisioningAllowed')
        }
      end
    end

    # Get a single user
    def user(user_id:)
      result = get("/users/#{user_id}")['data']
      {
        id: result['id'],
        username: result.dig('attributes', 'username'),
        first_name: result.dig('attributes', 'firstName'),
        last_name: result.dig('attributes', 'lastName'),
        email: result.dig('attributes', 'email'),
        roles: result.dig('attributes', 'roles'),
        all_apps_visible: result.dig('attributes', 'allAppsVisible'),
        provisioning_allowed: result.dig('attributes', 'provisioningAllowed')
      }
    end

    # Update user roles
    # roles: ADMIN, FINANCE, ACCOUNT_HOLDER, SALES, MARKETING, APP_MANAGER,
    #        DEVELOPER, ACCESS_TO_REPORTS, CUSTOMER_SUPPORT, CREATE_APPS,
    #        CLOUD_MANAGED_DEVELOPER_ID, CLOUD_MANAGED_APP_DISTRIBUTION
    def update_user(user_id:, roles: nil, all_apps_visible: nil)
      attributes = {}
      attributes[:roles] = roles if roles
      attributes[:allAppsVisible] = all_apps_visible unless all_apps_visible.nil?

      return nil if attributes.empty?

      patch("/users/#{user_id}", body: {
              data: {
                type: 'users',
                id: user_id,
                attributes: attributes
              }
            })
    end

    # Remove a user from the team
    def delete_user(user_id:)
      delete("/users/#{user_id}")
    end

    # List pending user invitations
    def user_invitations(limit: 100)
      get("/userInvitations?limit=#{limit}")['data'].map do |invite|
        {
          id: invite['id'],
          email: invite.dig('attributes', 'email'),
          first_name: invite.dig('attributes', 'firstName'),
          last_name: invite.dig('attributes', 'lastName'),
          roles: invite.dig('attributes', 'roles'),
          expiration_date: invite.dig('attributes', 'expirationDate'),
          all_apps_visible: invite.dig('attributes', 'allAppsVisible'),
          provisioning_allowed: invite.dig('attributes', 'provisioningAllowed')
        }
      end
    end

    # Invite a new user
    def create_user_invitation(email:, first_name:, last_name:, roles:,
                               all_apps_visible: true, provisioning_allowed: false,
                               visible_app_ids: [])
      relationships = {}

      if visible_app_ids.any?
        relationships[:visibleApps] = {
          data: visible_app_ids.map { |id| { type: 'apps', id: id } }
        }
      end

      body = {
        data: {
          type: 'userInvitations',
          attributes: {
            email: email,
            firstName: first_name,
            lastName: last_name,
            roles: roles,
            allAppsVisible: all_apps_visible,
            provisioningAllowed: provisioning_allowed
          }
        }
      }

      body[:data][:relationships] = relationships if relationships.any?

      result = post('/userInvitations', body: body)

      {
        id: result['data']['id'],
        email: result['data'].dig('attributes', 'email'),
        roles: result['data'].dig('attributes', 'roles'),
        expiration_date: result['data'].dig('attributes', 'expirationDate')
      }
    end

    # Cancel a pending user invitation
    def delete_user_invitation(invitation_id:)
      delete("/userInvitations/#{invitation_id}")
    end

    # ─────────────────────────────────────────────────────────────────────────
    # App Privacy Methods
    # ─────────────────────────────────────────────────────────────────────────

    # Get app data usage declarations (privacy labels)
    def app_data_usages(target_app_id: nil)
      target_app_id ||= @app_id
      # First get the app info
      infos = app_info(target_app_id: target_app_id)
      return [] if infos.empty?

      # Get the most recent app info (first one)
      app_info_id = infos.first[:id]

      get("/appInfos/#{app_info_id}/appDataUsages")['data'].map do |usage|
        {
          id: usage['id'],
          category: usage.dig('attributes', 'category'),
          purposes: usage.dig('attributes', 'purposes'),
          data_protection: usage.dig('attributes', 'dataProtection')
        }
      end
    rescue ApiError => e
      return [] if e.message.include?('Not found')

      raise
    end

    # List available data usage categories
    def app_data_usage_categories
      [
        { id: 'PAYMENT_INFORMATION', name: 'Payment Info' },
        { id: 'CREDIT_INFORMATION', name: 'Credit Info' },
        { id: 'OTHER_FINANCIAL_INFORMATION', name: 'Other Financial Info' },
        { id: 'PRECISE_LOCATION', name: 'Precise Location' },
        { id: 'COARSE_LOCATION', name: 'Coarse Location' },
        { id: 'SENSITIVE_INFORMATION', name: 'Sensitive Info' },
        { id: 'PHYSICAL_HEALTH', name: 'Health' },
        { id: 'FITNESS', name: 'Fitness' },
        { id: 'EMAIL_ADDRESS', name: 'Email Address' },
        { id: 'NAME', name: 'Name' },
        { id: 'PHONE_NUMBER', name: 'Phone Number' },
        { id: 'PHYSICAL_ADDRESS', name: 'Physical Address' },
        { id: 'OTHER_USER_CONTACT_INFO', name: 'Other Contact Info' },
        { id: 'USER_ID', name: 'User ID' },
        { id: 'DEVICE_ID', name: 'Device ID' },
        { id: 'OTHER_USER_OR_DEVICE_ID', name: 'Other ID' },
        { id: 'PURCHASE_HISTORY', name: 'Purchase History' },
        { id: 'PRODUCT_INTERACTION', name: 'Product Interaction' },
        { id: 'ADVERTISING_DATA', name: 'Advertising Data' },
        { id: 'OTHER_USAGE_DATA', name: 'Other Usage Data' },
        { id: 'CRASH_DATA', name: 'Crash Data' },
        { id: 'PERFORMANCE_DATA', name: 'Performance Data' },
        { id: 'OTHER_DIAGNOSTIC_DATA', name: 'Other Diagnostic Data' },
        { id: 'BROWSING_HISTORY', name: 'Browsing History' },
        { id: 'SEARCH_HISTORY', name: 'Search History' },
        { id: 'CONTACTS', name: 'Contacts' },
        { id: 'EMAILS_OR_TEXT_MESSAGES', name: 'Emails or Text Messages' },
        { id: 'PHOTOS_OR_VIDEOS', name: 'Photos or Videos' },
        { id: 'AUDIO_DATA', name: 'Audio Data' },
        { id: 'GAMEPLAY_CONTENT', name: 'Gameplay Content' },
        { id: 'CUSTOMER_SUPPORT', name: 'Customer Support' },
        { id: 'OTHER_USER_CONTENT', name: 'Other User Content' },
        { id: 'ENVIRONMENT_SCANNING', name: 'Environment Scanning' },
        { id: 'HANDS', name: 'Hands' },
        { id: 'HEAD', name: 'Head' },
        { id: 'OTHER_DATA_TYPES', name: 'Other Data Types' }
      ]
    end

    # List available data usage purposes
    def app_data_usage_purposes
      [
        { id: 'THIRD_PARTY_ADVERTISING', name: 'Third-Party Advertising' },
        { id: 'DEVELOPERS_ADVERTISING', name: "Developer's Advertising or Marketing" },
        { id: 'ANALYTICS', name: 'Analytics' },
        { id: 'PRODUCT_PERSONALIZATION', name: 'Product Personalization' },
        { id: 'APP_FUNCTIONALITY', name: 'App Functionality' },
        { id: 'OTHER_PURPOSES', name: 'Other Purposes' }
      ]
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

    private

    def request(method, path, params: {}, body: nil)
      uri = URI("#{BASE_URL}#{path}")
      uri.query = URI.encode_www_form(params) if params.any?

      # Use curl to avoid Ruby's SSL CRL verification issues
      curl_method = method.to_s.upcase
      curl_cmd = [
        'curl', '-s', '-X', curl_method,
        '-H', "Authorization: Bearer #{generate_token}",
        '-H', 'Content-Type: application/json'
      ]

      curl_cmd += ['-d', body.to_json] if body

      curl_cmd << uri.to_s

      output = `#{curl_cmd.shelljoin}`
      status = $CHILD_STATUS

      raise ApiError, "HTTP request failed with exit code #{status.exitstatus}" unless status.success?

      begin
        result = JSON.parse(output)
      rescue JSON::ParserError => e
        raise ApiError, "Invalid JSON response: #{e.message}"
      end

      # Check for API errors in the response
      if result['errors'].is_a?(Array) && result['errors'].any?
        error = result['errors'].first
        status_code = error['status']&.to_i || 500
        detail = error['detail'] || error['title'] || 'Unknown error'

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

      result
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
        exp: now + 20 * 60, # 20 minutes
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

    # Upload file chunks to the URLs provided by App Store Connect
    def upload_asset_chunks(file_data, upload_operations)
      upload_operations.each do |operation|
        method = operation['method']
        url = operation['url']
        offset = operation['offset']
        length = operation['length']
        headers = operation['requestHeaders'] || []

        # Extract the chunk of data for this operation
        chunk = file_data[offset, length]

        # Build curl command for the upload
        curl_cmd = ['curl', '-s', '-X', method]

        headers.each do |header|
          curl_cmd += ['-H', "#{header['name']}: #{header['value']}"]
        end

        # Write chunk to temp file and upload
        Tempfile.create(['chunk', '.bin']) do |temp_file|
          temp_file.binmode
          temp_file.write(chunk)
          temp_file.flush

          curl_cmd += ['--data-binary', "@#{temp_file.path}"]
          curl_cmd << url

          `#{curl_cmd.shelljoin}`
          status = $CHILD_STATUS

          raise ApiError, "Asset upload failed with exit code #{status.exitstatus}" unless status.success?
        end
      end
    end

    # Commit the upload by marking it as uploaded with checksum
    def commit_asset_upload(path:, type:, id:, checksum:)
      patch(path, body: {
              data: {
                type: type,
                id: id,
                attributes: {
                  uploaded: true,
                  sourceFileChecksum: checksum
                }
              }
            })
    end
  end
end
