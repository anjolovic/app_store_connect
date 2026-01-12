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
        screenshot_status = { total: 0, by_type: {} }

        # Check version state
        preparing = status[:versions].find { |v| v[:state] == 'PREPARE_FOR_SUBMISSION' }
        waiting = status[:versions].find { |v| v[:state] == 'WAITING_FOR_REVIEW' }
        rejected = status[:versions].find { |v| v[:state] == 'REJECTED' }

        issues << "Version #{rejected[:version]} was REJECTED - check App Store Connect for details" if rejected

        # Check subscription states
        sub_issues = status[:subscriptions].select { |s| s[:state] == 'MISSING_METADATA' }
        if sub_issues.any?
          issues << "Subscriptions missing metadata: #{sub_issues.map do |s|
            s[:product_id]
          end.join(', ')}"
        end

        sub_rejected = status[:subscriptions].select { |s| s[:state] == 'REJECTED' }
        issues << "Subscriptions rejected: #{sub_rejected.map { |s| s[:product_id] }.join(', ')}" if sub_rejected.any?

        # Check screenshots for preparing version
        if preparing
          version_id = preparing[:id]
          begin
            locs = app_store_version_localizations(version_id: version_id)
            # Check first localization for screenshots (usually en-US)
            if locs.any?
              loc = locs.first
              sets = app_screenshot_sets(localization_id: loc[:id])

              required_types = %w[APP_IPHONE_67 APP_IPHONE_65]
              sets.each do |set|
                screenshots = app_screenshots(screenshot_set_id: set[:id])
                count = screenshots.length
                screenshot_status[:by_type][set[:screenshot_display_type]] = count
                screenshot_status[:total] += count
              end

              missing_types = required_types - screenshot_status[:by_type].keys
              issues << "Missing screenshots for: #{missing_types.join(', ')}" if missing_types.any?

              issues << 'No screenshots uploaded' if screenshot_status[:total].zero?
            end
          rescue ApiError
            # Ignore screenshot check errors
          end
        end

        {
          ready: issues.empty?,
          current_state: if waiting
                           'WAITING_FOR_REVIEW'
                         else
                           (preparing ? 'PREPARE_FOR_SUBMISSION' : 'UNKNOWN')
                         end,
          issues: issues,
          status: status,
          screenshots: screenshot_status
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

      # Get review submission items (includes rejection state)
      def review_submission_items(submission_id:)
        get("/reviewSubmissions/#{submission_id}/items")['data'].map do |item|
          {
            id: item['id'],
            state: item.dig('attributes', 'state'),
            resolved: item.dig('attributes', 'resolved')
          }
        end
      end

      # Get app store version with rejection info
      def app_store_version_rejection(version_id:)
        # Try to get rejection info from the appStoreReviewDetail
        result = get("/appStoreVersions/#{version_id}?include=appStoreReviewDetail")
        version = result['data']
        included = result['included'] || []

        review_detail = included.find { |i| i['type'] == 'appStoreReviewDetails' }

        {
          id: version['id'],
          state: version.dig('attributes', 'appStoreState'),
          version_string: version.dig('attributes', 'versionString'),
          rejection_reason: review_detail&.dig('attributes', 'notes'),
          review_detail_id: review_detail&.dig('id')
        }
      end

      # Get rejection details from most recent rejected submission
      def rejection_info(target_app_id: nil)
        target_app_id ||= @app_id

        # Get versions to find rejected one
        versions = app_store_versions(target_app_id: target_app_id)

        # Check for any rejection state (REJECTED, METADATA_REJECTED, DEVELOPER_REJECTED, INVALID_BINARY)
        rejection_states = %w[REJECTED METADATA_REJECTED DEVELOPER_REJECTED INVALID_BINARY]
        rejected = versions.find { |v| rejection_states.include?(v.dig('attributes', 'appStoreState')) }

        # Get review submissions to find any with unresolved issues
        submissions = review_submissions(target_app_id: target_app_id, limit: 20)

        # Find submission with unresolved issues (rejection pending resolution)
        rejection_submission = submissions.find do |sub|
          sub.dig('attributes', 'state') == 'UNRESOLVED_ISSUES'
        end

        # If no rejected version but there's an unresolved submission, find the related version
        if !rejected && rejection_submission
          # Get the most recent non-ready version as likely the one with issues
          rejected = versions.find do |v|
            state = v.dig('attributes', 'appStoreState')
            %w[PREPARE_FOR_SUBMISSION WAITING_FOR_REVIEW IN_REVIEW].include?(state)
          end
        end

        return nil unless rejected || rejection_submission

        {
          version_id: rejected&.dig('id'),
          version_string: rejected&.dig('attributes', 'versionString'),
          state: rejected&.dig('attributes', 'appStoreState'),
          submission_id: rejection_submission&.dig('id'),
          submission_state: rejection_submission&.dig('attributes', 'state')
        }
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
