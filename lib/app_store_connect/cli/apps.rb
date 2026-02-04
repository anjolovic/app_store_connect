# frozen_string_literal: true

module AppStoreConnect
  class CLI
    # App status and overview CLI commands
    module Apps
      def cmd_status
        puts "\e[1mApp Store Connect Status\e[0m"
        puts '=' * 50
        puts

        status = client.app_status

        # App info
        puts "\e[1mApp:\e[0m #{status[:app][:name]} (#{status[:app][:bundle_id]})"
        puts

        # Versions
        puts "\e[1mVersions:\e[0m"
        status[:versions].each do |v|
          state_color = case v[:state]
                        when 'READY_FOR_SALE' then "\e[32m" # green
                        when 'WAITING_FOR_REVIEW', 'IN_REVIEW' then "\e[33m" # yellow
                        when 'REJECTED', 'DEVELOPER_REJECTED' then "\e[31m" # red
                        else "\e[0m"
                        end
          puts "  #{v[:version]}: #{state_color}#{v[:state]}\e[0m (#{v[:release_type]})"
        end
        puts

        # Latest review
        if status[:latest_review]
          r = status[:latest_review]
          puts "\e[1mLatest Review Submission:\e[0m"
          state_color = r[:state] == 'WAITING_FOR_REVIEW' ? "\e[33m" : "\e[32m"
          puts "  State: #{state_color}#{r[:state]}\e[0m"
          puts "  Platform: #{r[:platform]}"
          puts "  Submitted: #{Time.parse(r[:submitted]).strftime('%Y-%m-%d %H:%M %Z')}" if r[:submitted]
        end
        puts

        # Subscriptions
        puts "\e[1mSubscription Products:\e[0m"
        status[:subscriptions].sort_by { |s| s[:group_level] }.each do |s|
          state_color = case s[:state]
                        when 'APPROVED', 'READY_TO_SUBMIT' then "\e[32m"
                        when 'WAITING_FOR_REVIEW', 'IN_REVIEW' then "\e[33m"
                        when 'REJECTED', 'MISSING_METADATA' then "\e[31m"
                        else "\e[0m"
                        end
          puts "  #{s[:name]}: #{state_color}#{s[:state]}\e[0m (Level #{s[:group_level]})"
          puts "    Product ID: #{s[:product_id]}"
        end
      end

      def cmd_review
        puts "\e[1mReview Submissions\e[0m"
        puts '=' * 50
        puts

        reviews = client.review_submissions(limit: 10)

        if reviews.empty?
          puts 'No review submissions found.'
          return
        end

        reviews.each_with_index do |r, i|
          attrs = r['attributes']
          state = attrs['state']
          state_color = case state
                        when 'COMPLETE' then "\e[32m"
                        when 'WAITING_FOR_REVIEW', 'IN_REVIEW' then "\e[33m"
                        when 'REJECTED' then "\e[31m"
                        else "\e[0m"
                        end

          submitted = attrs['submittedDate'] ? Time.parse(attrs['submittedDate']).strftime('%Y-%m-%d %H:%M %Z') : 'N/A'

          puts "#{i + 1}. #{state_color}#{state}\e[0m"
          puts "   Platform: #{attrs['platform']}"
          puts "   Submitted: #{submitted}"
          puts
        end
      end

      def cmd_rejection
        puts "\e[1mRejection Details\e[0m"
        puts '=' * 50
        puts

        rejection = client.rejection_info

        unless rejection
          puts "\e[32mNo rejected versions found.\e[0m"
          return
        end

        if rejection[:state] && %w[REJECTED METADATA_REJECTED INVALID_BINARY].include?(rejection[:state])
          puts "\e[31mVersion #{rejection[:version_string]} was REJECTED\e[0m"
        elsif rejection[:submission_state] == 'UNRESOLVED_ISSUES'
          puts "\e[31mSubmission has UNRESOLVED ISSUES (rejection pending)\e[0m"
          puts "Version: #{rejection[:version_string]}" if rejection[:version_string]
        else
          puts "\e[33mVersion #{rejection[:version_string]} - #{rejection[:state]}\e[0m"
        end
        puts
        puts "Version ID: #{rejection[:version_id]}" if rejection[:version_id]
        puts "State: #{rejection[:state]}" if rejection[:state]

        if rejection[:submission_id]
          puts "Submission ID: #{rejection[:submission_id]}"
          puts "Submission State: #{rejection[:submission_state]}"

          # Try to get review submission items for more details
          begin
            items = client.review_submission_items(submission_id: rejection[:submission_id])
            if items.any?
              puts
              puts "\e[1mSubmission Items:\e[0m"
              items.each do |item|
                state_color = item[:state] == 'REJECTED' ? "\e[31m" : "\e[32m"
                resolved = item[:resolved] ? ' (resolved)' : ''
                puts "  - #{state_color}#{item[:state]}\e[0m#{resolved}"
              end
            end
          rescue StandardError => e
            puts "\e[33mCould not fetch submission items: #{e.message}\e[0m"
          end
        end

        # Try to get Resolution Center messages with actual rejection reason
        begin
          unless rejection[:submission_id]
            puts "\e[33mNo submission ID found - cannot fetch Resolution Center messages\e[0m"
            raise StandardError, 'No submission ID'
          end

          threads = client.resolution_center_threads(submission_id: rejection[:submission_id])
          thread_data = threads['data'] || []

          if thread_data.any?
            puts
            puts "\e[1mResolution Center Messages:\e[0m"

            thread_data.each do |thread|
              thread_id = thread['id']
              thread_type = thread.dig('attributes', 'threadType')
              puts "  Thread: #{thread_type}"

              # Fetch messages for this thread
              begin
                messages = client.rejection_reasons(thread_id: thread_id)
                messages.each do |msg|
                  body = msg[:body]
                  date = msg[:created_date]

                  next unless body

                  puts
                  puts "  \e[1mDate:\e[0m #{date}"
                  puts "  \e[1mMessage:\e[0m"
                  # Strip HTML tags for CLI display
                  plain_text = body.to_s
                                   .gsub(%r{<br\s*/?>}, "\n")
                                   .gsub('</p>', "\n")
                                   .gsub(/<[^>]+>/, '')
                                   .gsub('&nbsp;', ' ')
                                   .gsub('&amp;', '&')
                                   .gsub('&lt;', '<')
                                   .gsub('&gt;', '>')
                                   .gsub('&quot;', '"')
                  plain_text.split("\n").each { |line| puts "    #{line.strip}" unless line.strip.empty? }
                end
              rescue StandardError => e
                puts "  \e[33mCould not fetch messages: #{e.message}\e[0m"
              end
            end
          else
            puts "\e[33mNo Resolution Center threads found for this submission\e[0m"
          end
        rescue StandardError => e
          # IRIS API may not work with JWT auth - fall back gracefully
          puts
          puts "\e[33mCould not fetch Resolution Center messages: #{e.message}\e[0m"
        end

        # Try to get more rejection details from the version
        begin
          version_info = client.app_store_version_rejection(version_id: rejection[:version_id])
          if version_info[:rejection_reason]
            puts
            puts "\e[1mReview Notes:\e[0m"
            puts "  #{version_info[:rejection_reason]}"
          end
        rescue StandardError => e
          puts "\e[33mCould not fetch version details: #{e.message}\e[0m"
        end

        puts
        puts "\e[33mNote: If messages are not shown, check the Resolution Center at:\e[0m"
        puts '      https://appstoreconnect.apple.com'
      end

      def cmd_session
        puts "\e[1mSession Status\e[0m"
        puts '=' * 50
        puts

        if client.session_available?
          puts "\e[32mSession available\e[0m"
          puts '  Resolution Center access: enabled'
          puts '  Rejection messages: available'
        else
          puts "\e[33mNo session found\e[0m"
          puts
          puts 'To enable Resolution Center access (rejection messages):'
          puts
          puts '  1. Install fastlane (if not installed):'
          puts "     \e[36mgem install fastlane\e[0m"
          puts
          puts '  2. Generate session token:'
          puts "     \e[36mfastlane spaceauth -u your@apple.id\e[0m"
          puts
          puts '  3. Set the environment variable:'
          puts "     \e[36mexport FASTLANE_SESSION=\"...\"\e[0m"
          puts '     (copy the output from step 2)'
          puts
          puts '  4. Run rejection command again:'
          puts "     \e[36masc rejection\e[0m"
        end
      end

      def cmd_builds
        puts "\e[1mRecent Builds\e[0m"
        puts '=' * 50
        puts

        builds = client.builds(limit: 10)

        if builds.empty?
          puts 'No builds found.'
          return
        end

        builds.each do |b|
          state_color = case b[:processing_state]
                        when 'VALID' then "\e[32m"
                        when 'PROCESSING' then "\e[33m"
                        when 'FAILED', 'INVALID' then "\e[31m"
                        else "\e[0m"
                        end

          uploaded = b[:uploaded] ? Time.parse(b[:uploaded]).strftime('%Y-%m-%d %H:%M %Z') : 'N/A'

          puts "Build #{b[:version]}"
          puts "  State: #{state_color}#{b[:processing_state]}\e[0m"
          puts "  Audience: #{b[:build_audience_type]}"
          puts "  Uploaded: #{uploaded}"
          puts
        end
      end

      def cmd_apps
        puts "\e[1mAll Apps\e[0m"
        puts '=' * 50
        puts

        apps = client.apps

        apps.each do |app|
          puts "\e[1m#{app[:name]}\e[0m"
          puts "  ID: #{app[:id]}"
          puts "  Bundle ID: #{app[:bundle_id]}"
          puts "  SKU: #{app[:sku]}"
          puts
        end
      end

      def cmd_ready
        puts "\e[1mSubmission Readiness Check\e[0m"
        puts '=' * 50
        puts

        result = client.submission_readiness

        if json?
          output_json(result)
          return
        end

        if result[:ready]
          puts "\e[32mApp appears ready for submission!\e[0m"
        else
          puts "\e[31mIssues found:\e[0m"
          result[:issues].each do |issue|
            puts "  - #{issue}"
          end
        end

        puts
        puts "Current state: #{result[:current_state]}"

        missing_subs = (result.dig(:status, :subscriptions) || []).select { |s| s[:state] == 'MISSING_METADATA' }
        if missing_subs.any?
          puts
          puts "\e[1mSubscriptions Missing Metadata:\e[0m"
          missing_subs.each do |sub|
            puts
            puts "\e[1m#{sub[:product_id]}\e[0m (#{sub[:name] || 'Subscription'})"
            subscription_metadata_status(sub[:id], product_id: sub[:product_id]).each do |line|
              puts "  - #{line}"
            end
          end
        end

        # Show screenshot status
        if result[:screenshots] && result[:screenshots][:total].positive?
          puts
          puts "\e[1mScreenshots:\e[0m"
          result[:screenshots][:by_type].each do |type, count|
            puts "  #{type}: #{count} screenshot(s)"
          end
          puts "  Total: #{result[:screenshots][:total]}"
        elsif result[:screenshots]
          puts
          puts "\e[33mScreenshots: None uploaded\e[0m"
        end
      end
    end
  end
end
