# frozen_string_literal: true

module AppStoreConnect
  class Client
    # App and version management methods
    module Apps
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

      # List all apps
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

      # Get app store versions
      def app_store_versions(target_app_id: nil)
        target_app_id ||= @app_id
        get("/apps/#{target_app_id}/appStoreVersions")['data']
      end

      # Get review submissions
      def review_submissions(target_app_id: nil, limit: 10)
        target_app_id ||= @app_id
        get("/apps/#{target_app_id}/reviewSubmissions?limit=#{limit}")['data']
      end

      # Get builds
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

      # Get beta app review detail
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
    end
  end
end
