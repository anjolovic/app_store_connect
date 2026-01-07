# frozen_string_literal: true

module AppStoreConnect
  # Command-line interface for App Store Connect API
  #
  # Usage:
  #   asc status      # Full app status summary
  #   asc review      # Check review submission status
  #   asc subs        # List subscription products
  #   asc builds      # List recent builds
  #   asc apps        # List all apps
  #   asc ready       # Check if ready for submission
  #   asc help        # Show help
  #
  class CLI
    COMMANDS = %w[status review subs subscriptions builds apps ready help
                   review-info update-review-notes cancel-review submit
                   sub-details update-sub-description version-info update-whats-new].freeze

    def initialize(args)
      @command = args.first || "status"
      @options = args.drop(1)
    end

    def run
      unless COMMANDS.include?(@command)
        puts "Unknown command: #{@command}"
        puts "Run 'asc help' for usage"
        exit 1
      end

      send("cmd_#{@command.gsub('-', '_')}")
    rescue ConfigurationError => e
      puts "\e[31mConfiguration Error:\e[0m #{e.message}"
      puts
      puts "Run 'asc help' for setup instructions"
      exit 1
    rescue ApiError => e
      puts "\e[31mAPI Error:\e[0m #{e.message}"
      exit 1
    end

    private

    def client
      @client ||= Client.new
    end

    def cmd_status
      puts "\e[1mApp Store Connect Status\e[0m"
      puts "=" * 50
      puts

      status = client.app_status

      # App info
      puts "\e[1mApp:\e[0m #{status[:app][:name]} (#{status[:app][:bundle_id]})"
      puts

      # Versions
      puts "\e[1mVersions:\e[0m"
      status[:versions].each do |v|
        state_color = case v[:state]
        when "READY_FOR_SALE" then "\e[32m" # green
        when "WAITING_FOR_REVIEW", "IN_REVIEW" then "\e[33m" # yellow
        when "REJECTED", "DEVELOPER_REJECTED" then "\e[31m" # red
        else "\e[0m"
        end
        puts "  #{v[:version]}: #{state_color}#{v[:state]}\e[0m (#{v[:release_type]})"
      end
      puts

      # Latest review
      if status[:latest_review]
        r = status[:latest_review]
        puts "\e[1mLatest Review Submission:\e[0m"
        state_color = r[:state] == "WAITING_FOR_REVIEW" ? "\e[33m" : "\e[32m"
        puts "  State: #{state_color}#{r[:state]}\e[0m"
        puts "  Platform: #{r[:platform]}"
        puts "  Submitted: #{Time.parse(r[:submitted]).strftime('%Y-%m-%d %H:%M %Z')}" if r[:submitted]
      end
      puts

      # Subscriptions
      puts "\e[1mSubscription Products:\e[0m"
      status[:subscriptions].sort_by { |s| s[:group_level] }.each do |s|
        state_color = case s[:state]
        when "APPROVED", "READY_TO_SUBMIT" then "\e[32m"
        when "WAITING_FOR_REVIEW", "IN_REVIEW" then "\e[33m"
        when "REJECTED", "MISSING_METADATA" then "\e[31m"
        else "\e[0m"
        end
        puts "  #{s[:name]}: #{state_color}#{s[:state]}\e[0m (Level #{s[:group_level]})"
        puts "    Product ID: #{s[:product_id]}"
      end
    end

    def cmd_review
      puts "\e[1mReview Submissions\e[0m"
      puts "=" * 50
      puts

      reviews = client.review_submissions(limit: 10)

      if reviews.empty?
        puts "No review submissions found."
        return
      end

      reviews.each_with_index do |r, i|
        attrs = r["attributes"]
        state = attrs["state"]
        state_color = case state
        when "COMPLETE" then "\e[32m"
        when "WAITING_FOR_REVIEW", "IN_REVIEW" then "\e[33m"
        when "REJECTED" then "\e[31m"
        else "\e[0m"
        end

        submitted = attrs["submittedDate"] ? Time.parse(attrs["submittedDate"]).strftime("%Y-%m-%d %H:%M %Z") : "N/A"

        puts "#{i + 1}. #{state_color}#{state}\e[0m"
        puts "   Platform: #{attrs['platform']}"
        puts "   Submitted: #{submitted}"
        puts
      end
    end

    def cmd_subs
      cmd_subscriptions
    end

    def cmd_subscriptions
      puts "\e[1mSubscription Products\e[0m"
      puts "=" * 50
      puts

      subs = client.subscriptions

      if subs.empty?
        puts "No subscription products found."
        return
      end

      subs.sort_by { |s| s.dig("attributes", "groupLevel") || 0 }.each do |s|
        attrs = s["attributes"]
        state = attrs["state"]
        state_color = case state
        when "APPROVED", "READY_TO_SUBMIT" then "\e[32m"
        when "WAITING_FOR_REVIEW", "IN_REVIEW" then "\e[33m"
        when "REJECTED", "MISSING_METADATA" then "\e[31m"
        else "\e[0m"
        end

        puts "\e[1m#{attrs['name']}\e[0m"
        puts "  Product ID: #{attrs['productId']}"
        puts "  State: #{state_color}#{state}\e[0m"
        puts "  Group Level: #{attrs['groupLevel']} (higher = more expensive)"
        puts
      end
    end

    def cmd_builds
      puts "\e[1mRecent Builds\e[0m"
      puts "=" * 50
      puts

      builds = client.builds(limit: 10)

      if builds.empty?
        puts "No builds found."
        return
      end

      builds.each do |b|
        state_color = case b[:processing_state]
        when "VALID" then "\e[32m"
        when "PROCESSING" then "\e[33m"
        when "FAILED", "INVALID" then "\e[31m"
        else "\e[0m"
        end

        uploaded = b[:uploaded] ? Time.parse(b[:uploaded]).strftime("%Y-%m-%d %H:%M %Z") : "N/A"

        puts "Build #{b[:version]}"
        puts "  State: #{state_color}#{b[:processing_state]}\e[0m"
        puts "  Audience: #{b[:build_audience_type]}"
        puts "  Uploaded: #{uploaded}"
        puts
      end
    end

    def cmd_apps
      puts "\e[1mAll Apps\e[0m"
      puts "=" * 50
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
      puts "=" * 50
      puts

      result = client.submission_readiness

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
    end

    def cmd_review_info
      puts "\e[1mApp Review Details\e[0m"
      puts "=" * 50
      puts

      # Get the version that's waiting for review or being prepared
      versions = client.app_store_versions
      active_version = versions.find { |v| v.dig("attributes", "appStoreState") == "WAITING_FOR_REVIEW" }
      active_version ||= versions.find { |v| v.dig("attributes", "appStoreState") == "PREPARE_FOR_SUBMISSION" }

      unless active_version
        puts "No active version found."
        return
      end

      version_id = active_version["id"]
      version_string = active_version.dig("attributes", "versionString")
      puts "\e[1mVersion:\e[0m #{version_string} (#{active_version.dig('attributes', 'appStoreState')})"
      puts

      # Get review detail
      begin
        detail = client.app_store_review_detail(version_id: version_id)
        if detail
          puts "\e[1mReview Contact:\e[0m"
          puts "  Name: #{detail[:contact_first_name]} #{detail[:contact_last_name]}"
          puts "  Email: #{detail[:contact_email]}"
          puts "  Phone: #{detail[:contact_phone]}"
          puts
          puts "\e[1mDemo Account:\e[0m"
          puts "  Required: #{detail[:demo_account_required]}"
          puts "  Username: #{detail[:demo_account_name] || '(not set)'}"
          puts "  Password: #{detail[:demo_account_password] ? '****' : '(not set)'}"
          puts
          puts "\e[1mNotes for Reviewer:\e[0m"
          puts "  #{detail[:notes] || '(none)'}"
        else
          puts "No review detail found for this version."
        end
      rescue ApiError => e
        puts "\e[33mCould not fetch review detail: #{e.message}\e[0m"
      end
    end

    def cmd_update_review_notes
      notes = @options.join(" ")
      if notes.empty?
        puts "\e[31mUsage: asc update-review-notes \"Your notes for the reviewer\"\e[0m"
        exit 1
      end

      versions = client.app_store_versions
      active_version = versions.find { |v| v.dig("attributes", "appStoreState") == "WAITING_FOR_REVIEW" }
      active_version ||= versions.find { |v| v.dig("attributes", "appStoreState") == "PREPARE_FOR_SUBMISSION" }

      unless active_version
        puts "\e[31mNo active version found to update.\e[0m"
        exit 1
      end

      version_id = active_version["id"]
      detail = client.app_store_review_detail(version_id: version_id)

      unless detail
        puts "\e[31mNo review detail found for this version.\e[0m"
        exit 1
      end

      client.update_app_store_review_detail(detail_id: detail[:id], notes: notes)
      puts "\e[32mReview notes updated successfully!\e[0m"
      puts "  Version: #{active_version.dig('attributes', 'versionString')}"
      puts "  Notes: #{notes}"
    end

    def cmd_cancel_review
      reviews = client.review_submissions(limit: 1)
      pending = reviews.find { |r| r.dig("attributes", "state") == "WAITING_FOR_REVIEW" }

      unless pending
        puts "\e[33mNo pending review submission to cancel.\e[0m"
        return
      end

      print "Cancel review submission? (y/N): "
      confirm = $stdin.gets.chomp.downcase

      if confirm == "y"
        client.cancel_review_submission(submission_id: pending["id"])
        puts "\e[32mReview submission cancelled.\e[0m"
      else
        puts "Cancelled."
      end
    end

    def cmd_submit
      versions = client.app_store_versions
      ready_version = versions.find { |v| v.dig("attributes", "appStoreState") == "READY_FOR_SUBMISSION" }

      unless ready_version
        prepare_version = versions.find { |v| v.dig("attributes", "appStoreState") == "PREPARE_FOR_SUBMISSION" }
        if prepare_version
          puts "\e[33mVersion #{prepare_version.dig('attributes', 'versionString')} is still being prepared.\e[0m"
          puts "Complete all required metadata in App Store Connect before submitting."
        else
          puts "\e[33mNo version ready for submission.\e[0m"
        end
        return
      end

      version_string = ready_version.dig("attributes", "versionString")
      print "Submit version #{version_string} for review? (y/N): "
      confirm = $stdin.gets.chomp.downcase

      if confirm == "y"
        client.create_review_submission
        puts "\e[32mVersion #{version_string} submitted for review!\e[0m"
      else
        puts "Cancelled."
      end
    end

    def cmd_sub_details
      puts "\e[1mSubscription Details\e[0m"
      puts "=" * 50
      puts

      subs = client.subscriptions

      subs.sort_by { |s| s.dig("attributes", "groupLevel") || 0 }.each do |sub|
        attrs = sub["attributes"]
        sub_id = sub["id"]

        puts "\e[1m#{attrs['name']}\e[0m (ID: #{sub_id})"
        puts "  Product ID: #{attrs['productId']}"
        puts "  State: #{attrs['state']}"
        puts "  Group Level: #{attrs['groupLevel']}"
        puts

        # Get localizations
        begin
          locs = client.subscription_localizations(subscription_id: sub_id)
          if locs.any?
            puts "  \e[1mLocalizations:\e[0m"
            locs.each do |loc|
              puts "    #{loc[:locale]}: #{loc[:name]}"
              puts "      Description: #{loc[:description] || '(none)'}"
            end
          end
        rescue ApiError => e
          puts "  \e[33mCould not fetch localizations: #{e.message}\e[0m"
        end
        puts
      end
    end

    def cmd_update_sub_description
      if @options.length < 2
        puts "\e[31mUsage: asc update-sub-description <product_id> \"New description\"\e[0m"
        puts "Example: asc update-sub-description com.example.app.plan.starter.monthly \"Access basic features\""
        exit 1
      end

      product_id = @options[0]
      description = @options[1..].join(" ")

      subs = client.subscriptions
      sub = subs.find { |s| s.dig("attributes", "productId") == product_id }

      unless sub
        puts "\e[31mSubscription not found: #{product_id}\e[0m"
        exit 1
      end

      sub_id = sub["id"]
      locs = client.subscription_localizations(subscription_id: sub_id)
      en_loc = locs.find { |l| l[:locale] == "en-US" }

      unless en_loc
        puts "\e[33mNo en-US localization found. Creating one...\e[0m"
        client.create_subscription_localization(
          subscription_id: sub_id,
          locale: "en-US",
          name: sub.dig("attributes", "name"),
          description: description
        )
        puts "\e[32mCreated en-US localization with description.\e[0m"
        return
      end

      client.update_subscription_localization(localization_id: en_loc[:id], description: description)
      puts "\e[32mUpdated subscription description!\e[0m"
      puts "  Product: #{product_id}"
      puts "  Description: #{description}"
    end

    def cmd_version_info
      puts "\e[1mVersion Localizations\e[0m"
      puts "=" * 50
      puts

      versions = client.app_store_versions
      active_version = versions.find { |v| v.dig("attributes", "appStoreState") == "WAITING_FOR_REVIEW" }
      active_version ||= versions.find { |v| v.dig("attributes", "appStoreState") == "PREPARE_FOR_SUBMISSION" }
      active_version ||= versions.first

      unless active_version
        puts "No versions found."
        return
      end

      version_id = active_version["id"]
      version_string = active_version.dig("attributes", "versionString")
      state = active_version.dig("attributes", "appStoreState")

      puts "\e[1mVersion:\e[0m #{version_string} (#{state})"
      puts

      locs = client.app_store_version_localizations(version_id: version_id)

      locs.each do |loc|
        puts "\e[1m#{loc[:locale]}:\e[0m"
        puts "  Description: #{(loc[:description] || '(none)')[0..100]}..."
        puts "  What's New: #{loc[:whats_new] || '(none)'}"
        puts "  Keywords: #{loc[:keywords] || '(none)'}"
        puts "  Support URL: #{loc[:support_url] || '(none)'}"
        puts
      end
    end

    def cmd_update_whats_new
      whats_new = @options.join(" ")
      if whats_new.empty?
        puts "\e[31mUsage: asc update-whats-new \"What's new in this version\"\e[0m"
        exit 1
      end

      versions = client.app_store_versions
      active_version = versions.find { |v| v.dig("attributes", "appStoreState") == "WAITING_FOR_REVIEW" }
      active_version ||= versions.find { |v| v.dig("attributes", "appStoreState") == "PREPARE_FOR_SUBMISSION" }

      unless active_version
        puts "\e[31mNo active version found to update.\e[0m"
        exit 1
      end

      version_id = active_version["id"]
      locs = client.app_store_version_localizations(version_id: version_id)
      en_loc = locs.find { |l| l[:locale] == "en-US" }

      unless en_loc
        puts "\e[31mNo en-US localization found.\e[0m"
        exit 1
      end

      client.update_app_store_version_localization(localization_id: en_loc[:id], whats_new: whats_new)
      puts "\e[32mUpdated \"What's New\" text!\e[0m"
      puts "  Version: #{active_version.dig('attributes', 'versionString')}"
      puts "  What's New: #{whats_new}"
    end

    def cmd_help
      puts <<~HELP
        \e[1mApp Store Connect CLI\e[0m

        A command-line tool for checking and updating App Store Connect.

        \e[1mUSAGE:\e[0m
          asc <command> [options]

        \e[1mREAD COMMANDS:\e[0m
          status            Full app status summary (default)
          review            Check review submission status
          review-info       Show review contact info and notes
          subs              List subscription products
          sub-details       Detailed subscription info with localizations
          version-info      Show version localizations (description, what's new)
          builds            List recent builds
          apps              List all apps in your account
          ready             Check if ready for submission

        \e[1mWRITE COMMANDS (respond to Apple Review requests):\e[0m
          update-review-notes "notes"           Update notes for App Review
          update-whats-new "text"               Update "What's New" release notes
          update-sub-description <id> "desc"    Update subscription description
          submit                                Submit version for App Review
          cancel-review                         Cancel pending review submission

          help              Show this help message

        \e[1mSETUP:\e[0m

        1. Generate an App Store Connect API key:
           - Go to https://appstoreconnect.apple.com
           - Navigate to Users and Access > Integrations > App Store Connect API
           - Click "Generate API Key"
           - Select role: Admin or App Manager
           - Download the .p8 file (you can only download once!)
           - Note the Key ID shown

        2. Set environment variables:

           APP_STORE_CONNECT_KEY_ID=YOUR_KEY_ID
           APP_STORE_CONNECT_ISSUER_ID=YOUR_ISSUER_ID
           APP_STORE_CONNECT_PRIVATE_KEY_PATH=/path/to/AuthKey_XXXX.p8
           APP_STORE_CONNECT_APP_ID=YOUR_APP_ID
           APP_STORE_CONNECT_BUNDLE_ID=com.example.app

           Note: The Issuer ID is the same for all keys in your team.
           It's shown at the top of the App Store Connect API keys page.

        3. Move your .p8 key to a secure location:
           mkdir -p ~/.config/app_store_connect/keys
           mv AuthKey_XXXX.p8 ~/.config/app_store_connect/keys/
           chmod 600 ~/.config/app_store_connect/keys/AuthKey_XXXX.p8

        \e[1mEXAMPLES:\e[0m
          asc                           # Show full status
          asc review-info               # View review details
          asc update-review-notes "Please test with demo account"
          asc update-whats-new "Bug fixes and performance improvements"
          asc sub-details               # View subscription localizations

        \e[1mRESPONDING TO APPLE REVIEW:\e[0m
          # If Apple requests updated reviewer notes:
          asc update-review-notes "Use demo account: test@example.com / password123"

          # If Apple requests updated release notes:
          asc update-whats-new "Fixed subscription flow issues"

          # If Apple requests subscription description update:
          asc update-sub-description com.example.app.plan.starter.monthly "Access to basic features"

        \e[1mUSE IN RUBY CODE:\e[0m
          require "app_store_connect"

          # Configure (optional if using env vars)
          AppStoreConnect.configure do |config|
            config.app_id = "123456789"
            config.bundle_id = "com.example.app"
          end

          client = AppStoreConnect::Client.new
          client.app_status
          client.review_submissions
          client.subscriptions
          client.subscription_localizations(subscription_id: "123")
          client.update_subscription_localization(localization_id: "456", description: "New desc")

      HELP
    end
  end
end
