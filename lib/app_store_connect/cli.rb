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
    COMMANDS = %w[status review rejection subs subscriptions builds apps ready help
                  review-info update-review-notes update-review-contact update-demo-account cancel-review submit create-review-detail
                  sub-details update-sub-description update-sub-note version-info update-whats-new
                  description update-description keywords update-keywords
                  urls update-marketing-url update-support-url
                  update-promotional-text update-privacy-url
                  iaps iap-details update-iap-note update-iap-description submit-iap
                  customer-reviews respond-review
                  upload-iap-screenshot delete-iap-screenshot
                  screenshots upload-screenshot upload-screenshots delete-screenshot
                  create-version release phased-release pause-release resume-release
                  complete-release enable-phased-release
                  pre-order enable-pre-order cancel-pre-order
                  testers tester-groups add-tester remove-tester
                  create-group delete-group group-testers add-to-group remove-from-group
                  testflight-builds distribute-build remove-build
                  beta-whats-new update-beta-whats-new
                  submit-beta-review beta-review-status
                  app-info age-rating categories update-app-name update-subtitle
                  availability territories pricing
                  users invitations invite-user remove-user cancel-invitation
                  privacy-labels].freeze

    def initialize(args)
      @command = args.first || 'status'
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

      puts "\e[31mVersion #{rejection[:version_string]} was REJECTED\e[0m"
      puts
      puts "Version ID: #{rejection[:version_id]}"
      puts "State: #{rejection[:state]}"

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
      puts "\e[33mNote: Detailed rejection reasons are available in the Resolution Center\e[0m"
      puts "      at https://appstoreconnect.apple.com"
    end

    def cmd_subs
      cmd_subscriptions
    end

    def cmd_subscriptions
      puts "\e[1mSubscription Products\e[0m"
      puts '=' * 50
      puts

      subs = client.subscriptions

      if subs.empty?
        puts 'No subscription products found.'
        return
      end

      subs.sort_by { |s| s.dig('attributes', 'groupLevel') || 0 }.each do |s|
        attrs = s['attributes']
        state = attrs['state']
        state_color = case state
                      when 'APPROVED', 'READY_TO_SUBMIT' then "\e[32m"
                      when 'WAITING_FOR_REVIEW', 'IN_REVIEW' then "\e[33m"
                      when 'REJECTED', 'MISSING_METADATA' then "\e[31m"
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

      if result[:ready]
        puts "\e[32m✓ App appears ready for submission!\e[0m"
      else
        puts "\e[31mIssues found:\e[0m"
        result[:issues].each do |issue|
          puts "  ✗ #{issue}"
        end
      end

      puts
      puts "Current state: #{result[:current_state]}"

      # Show screenshot status
      if result[:screenshots] && result[:screenshots][:total] > 0
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

    def cmd_review_info
      puts "\e[1mApp Review Details\e[0m"
      puts '=' * 50
      puts

      # Get the version that's waiting for review or being prepared
      versions = client.app_store_versions
      active_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'WAITING_FOR_REVIEW' }
      active_version ||= versions.find { |v| v.dig('attributes', 'appStoreState') == 'PREPARE_FOR_SUBMISSION' }

      unless active_version
        puts 'No active version found.'
        return
      end

      version_id = active_version['id']
      version_string = active_version.dig('attributes', 'versionString')
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
          puts 'No review detail found for this version.'
        end
      rescue ApiError => e
        puts "\e[33mCould not fetch review detail: #{e.message}\e[0m"
      end
    end

    def cmd_update_review_notes
      notes = @options.join(' ')
      if notes.empty?
        puts "\e[31mUsage: asc update-review-notes \"Your notes for the reviewer\"\e[0m"
        exit 1
      end

      versions = client.app_store_versions
      active_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'WAITING_FOR_REVIEW' }
      active_version ||= versions.find { |v| v.dig('attributes', 'appStoreState') == 'PREPARE_FOR_SUBMISSION' }

      unless active_version
        puts "\e[31mNo active version found to update.\e[0m"
        exit 1
      end

      version_id = active_version['id']
      detail = client.app_store_review_detail(version_id: version_id)

      unless detail
        # Auto-create review detail if it doesn't exist
        puts "\e[33mNo review detail found, creating one...\e[0m"
        result = client.create_app_store_review_detail(version_id: version_id, notes: notes)
        puts "\e[32mReview detail created with notes!\e[0m"
        puts "  Version: #{active_version.dig('attributes', 'versionString')}"
        puts "  Notes: #{notes}"
        return
      end

      client.update_app_store_review_detail(detail_id: detail[:id], notes: notes)
      puts "\e[32mReview notes updated successfully!\e[0m"
      puts "  Version: #{active_version.dig('attributes', 'versionString')}"
      puts "  Notes: #{notes}"
    end

    def cmd_update_review_contact
      # Parse arguments: --first-name, --last-name, --email, --phone
      first_name = nil
      last_name = nil
      email = nil
      phone = nil

      args = @options.dup
      while args.any?
        arg = args.shift
        case arg
        when '--first-name'
          first_name = args.shift
        when '--last-name'
          last_name = args.shift
        when '--email'
          email = args.shift
        when '--phone'
          phone = args.shift
        end
      end

      if [first_name, last_name, email, phone].all?(&:nil?)
        puts "\e[31mUsage: asc update-review-contact --first-name NAME --last-name NAME --email EMAIL --phone PHONE\e[0m"
        puts "  At least one option is required."
        exit 1
      end

      versions = client.app_store_versions
      active_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'WAITING_FOR_REVIEW' }
      active_version ||= versions.find { |v| v.dig('attributes', 'appStoreState') == 'PREPARE_FOR_SUBMISSION' }

      unless active_version
        puts "\e[31mNo active version found to update.\e[0m"
        exit 1
      end

      version_id = active_version['id']
      detail = client.app_store_review_detail(version_id: version_id)

      unless detail
        # Auto-create review detail if it doesn't exist
        puts "\e[33mNo review detail found, creating one...\e[0m"
        client.create_app_store_review_detail(
          version_id: version_id,
          contact_first_name: first_name,
          contact_last_name: last_name,
          contact_email: email,
          contact_phone: phone
        )
        puts "\e[32mReview detail created with contact info!\e[0m"
        puts "  Version: #{active_version.dig('attributes', 'versionString')}"
        puts "  First Name: #{first_name}" if first_name
        puts "  Last Name: #{last_name}" if last_name
        puts "  Email: #{email}" if email
        puts "  Phone: #{phone}" if phone
        return
      end

      client.update_app_store_review_detail(
        detail_id: detail[:id],
        contact_first_name: first_name,
        contact_last_name: last_name,
        contact_email: email,
        contact_phone: phone
      )
      puts "\e[32mReview contact updated successfully!\e[0m"
      puts "  Version: #{active_version.dig('attributes', 'versionString')}"
      puts "  First Name: #{first_name}" if first_name
      puts "  Last Name: #{last_name}" if last_name
      puts "  Email: #{email}" if email
      puts "  Phone: #{phone}" if phone
    end

    def cmd_update_demo_account
      # Parse arguments: --username, --password, --required
      username = nil
      password = nil
      required = nil

      args = @options.dup
      while args.any?
        arg = args.shift
        case arg
        when '--username'
          username = args.shift
        when '--password'
          password = args.shift
        when '--required'
          required = true
        when '--not-required'
          required = false
        end
      end

      if username.nil? && password.nil? && required.nil?
        puts "\e[31mUsage: asc update-demo-account --username USER --password PASS [--required|--not-required]\e[0m"
        puts "  At least one option is required."
        exit 1
      end

      versions = client.app_store_versions
      active_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'WAITING_FOR_REVIEW' }
      active_version ||= versions.find { |v| v.dig('attributes', 'appStoreState') == 'PREPARE_FOR_SUBMISSION' }

      unless active_version
        puts "\e[31mNo active version found to update.\e[0m"
        exit 1
      end

      version_id = active_version['id']
      detail = client.app_store_review_detail(version_id: version_id)

      unless detail
        # Auto-create review detail if it doesn't exist
        puts "\e[33mNo review detail found, creating one...\e[0m"
        client.create_app_store_review_detail(
          version_id: version_id,
          demo_account_name: username,
          demo_account_password: password,
          demo_account_required: required
        )
        puts "\e[32mReview detail created with demo account!\e[0m"
        puts "  Version: #{active_version.dig('attributes', 'versionString')}"
        puts "  Username: #{username}" if username
        puts "  Password: #{password ? '********' : '(not set)'}"
        puts "  Required: #{required}" unless required.nil?
        return
      end

      client.update_app_store_review_detail(
        detail_id: detail[:id],
        demo_account_name: username,
        demo_account_password: password,
        demo_account_required: required
      )
      puts "\e[32mDemo account updated successfully!\e[0m"
      puts "  Version: #{active_version.dig('attributes', 'versionString')}"
      puts "  Username: #{username}" if username
      puts "  Password: #{password ? '********' : '(not set)'}"
      puts "  Required: #{required}" unless required.nil?
    end

    def cmd_create_review_detail
      versions = client.app_store_versions
      active_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'WAITING_FOR_REVIEW' }
      active_version ||= versions.find { |v| v.dig('attributes', 'appStoreState') == 'PREPARE_FOR_SUBMISSION' }

      unless active_version
        puts "\e[31mNo active version found.\e[0m"
        exit 1
      end

      version_id = active_version['id']
      version_string = active_version.dig('attributes', 'versionString')

      # Check if review detail already exists
      existing = client.app_store_review_detail(version_id: version_id)
      if existing
        puts "\e[33mReview detail already exists for version #{version_string}.\e[0m"
        puts "  Detail ID: #{existing[:id]}"
        puts "  Notes: #{existing[:notes] || '(none)'}"
        return
      end

      # Parse optional arguments
      notes = nil
      contact_email = nil
      demo_account_name = nil
      demo_account_password = nil

      @options.each_with_index do |opt, i|
        case opt
        when '--notes'
          notes = @options[i + 1]
        when '--email'
          contact_email = @options[i + 1]
        when '--demo-user'
          demo_account_name = @options[i + 1]
        when '--demo-pass'
          demo_account_password = @options[i + 1]
        end
      end

      result = client.create_app_store_review_detail(
        version_id: version_id,
        notes: notes,
        contact_email: contact_email,
        demo_account_name: demo_account_name,
        demo_account_password: demo_account_password
      )

      puts "\e[32mReview detail created!\e[0m"
      puts "  Version: #{version_string}"
      puts "  Detail ID: #{result[:id]}"
      puts "  Notes: #{notes || '(none)'}"
    end

    def cmd_cancel_review
      reviews = client.review_submissions(limit: 1)
      pending = reviews.find { |r| r.dig('attributes', 'state') == 'WAITING_FOR_REVIEW' }

      unless pending
        puts "\e[33mNo pending review submission to cancel.\e[0m"
        return
      end

      print 'Cancel review submission? (y/N): '
      confirm = $stdin.gets.chomp.downcase

      if confirm == 'y'
        client.cancel_review_submission(submission_id: pending['id'])
        puts "\e[32mReview submission cancelled.\e[0m"
      else
        puts 'Cancelled.'
      end
    end

    def cmd_submit
      versions = client.app_store_versions
      ready_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'READY_FOR_SUBMISSION' }

      unless ready_version
        prepare_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'PREPARE_FOR_SUBMISSION' }
        if prepare_version
          puts "\e[33mVersion #{prepare_version.dig('attributes', 'versionString')} is still being prepared.\e[0m"
          puts 'Complete all required metadata in App Store Connect before submitting.'
        else
          puts "\e[33mNo version ready for submission.\e[0m"
        end
        return
      end

      version_string = ready_version.dig('attributes', 'versionString')
      print "Submit version #{version_string} for review? (y/N): "
      confirm = $stdin.gets.chomp.downcase

      if confirm == 'y'
        client.create_review_submission
        puts "\e[32mVersion #{version_string} submitted for review!\e[0m"
      else
        puts 'Cancelled.'
      end
    end

    def cmd_sub_details
      puts "\e[1mSubscription Details\e[0m"
      puts '=' * 50
      puts

      subs = client.subscriptions

      subs.sort_by { |s| s.dig('attributes', 'groupLevel') || 0 }.each do |sub|
        attrs = sub['attributes']
        sub_id = sub['id']

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
        puts 'Example: asc update-sub-description com.example.app.plan.starter.monthly "Access basic features"'
        exit 1
      end

      product_id = @options[0]
      description = @options[1..].join(' ')

      subs = client.subscriptions
      sub = subs.find { |s| s.dig('attributes', 'productId') == product_id }

      unless sub
        puts "\e[31mSubscription not found: #{product_id}\e[0m"
        exit 1
      end

      sub_id = sub['id']
      locs = client.subscription_localizations(subscription_id: sub_id)
      en_loc = locs.find { |l| l[:locale] == 'en-US' }

      unless en_loc
        puts "\e[33mNo en-US localization found. Creating one...\e[0m"
        client.create_subscription_localization(
          subscription_id: sub_id,
          locale: 'en-US',
          name: sub.dig('attributes', 'name'),
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

    def cmd_update_sub_note
      if @options.length < 2
        puts "\e[31mUsage: asc update-sub-note <product_id> \"Review note for Apple\"\e[0m"
        puts 'Example: asc update-sub-note com.example.app.plan.starter.monthly "This subscription unlocks premium features"'
        exit 1
      end

      product_id = @options[0]
      review_note = @options[1..].join(' ')

      subs = client.subscriptions
      sub = subs.find { |s| s.dig('attributes', 'productId') == product_id }

      unless sub
        puts "\e[31mSubscription not found: #{product_id}\e[0m"
        exit 1
      end

      client.update_subscription(subscription_id: sub['id'], review_note: review_note)
      puts "\e[32mUpdated subscription review note!\e[0m"
      puts "  Product: #{product_id}"
      puts "  Review Note: #{review_note}"
    end

    def cmd_version_info
      puts "\e[1mVersion Localizations\e[0m"
      puts '=' * 50
      puts

      versions = client.app_store_versions
      active_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'WAITING_FOR_REVIEW' }
      active_version ||= versions.find { |v| v.dig('attributes', 'appStoreState') == 'PREPARE_FOR_SUBMISSION' }
      active_version ||= versions.first

      unless active_version
        puts 'No versions found.'
        return
      end

      version_id = active_version['id']
      version_string = active_version.dig('attributes', 'versionString')
      state = active_version.dig('attributes', 'appStoreState')

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
      whats_new = @options.join(' ')
      if whats_new.empty?
        puts "\e[31mUsage: asc update-whats-new \"What's new in this version\"\e[0m"
        exit 1
      end

      versions = client.app_store_versions
      active_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'WAITING_FOR_REVIEW' }
      active_version ||= versions.find { |v| v.dig('attributes', 'appStoreState') == 'PREPARE_FOR_SUBMISSION' }

      unless active_version
        puts "\e[31mNo active version found to update.\e[0m"
        exit 1
      end

      version_id = active_version['id']
      locs = client.app_store_version_localizations(version_id: version_id)
      en_loc = locs.find { |l| l[:locale] == 'en-US' }

      unless en_loc
        puts "\e[31mNo en-US localization found.\e[0m"
        exit 1
      end

      begin
        client.update_app_store_version_localization(localization_id: en_loc[:id], whats_new: whats_new)
        puts "\e[32mUpdated \"What's New\" text!\e[0m"
        puts "  Version: #{active_version.dig('attributes', 'versionString')}"
        puts "  What's New: #{whats_new}"
      rescue ApiError => e
        if e.message.include?('cannot be edited') || e.message.include?('409')
          # Check if this is the first version (no previous versions in READY_FOR_SALE)
          released_versions = versions.select { |v| v.dig('attributes', 'appStoreState') == 'READY_FOR_SALE' }
          if released_versions.empty?
            puts "\e[33mCannot update \"What's New\" for the initial app release.\e[0m"
            puts
            puts 'The "What\'s New" field is only available for app updates, not the first version.'
            puts 'This field will become available when you submit your first update.'
          else
            puts "\e[31mCannot update \"What's New\" at this time.\e[0m"
            puts "The version may be in a state that doesn't allow edits."
          end
          exit 1
        else
          raise
        end
      end
    end

    def cmd_description
      locale = @options.first || 'en-US'

      puts "\e[1mApp Description\e[0m"
      puts '=' * 50
      puts

      versions = client.app_store_versions
      active_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'WAITING_FOR_REVIEW' }
      active_version ||= versions.find { |v| v.dig('attributes', 'appStoreState') == 'PREPARE_FOR_SUBMISSION' }
      active_version ||= versions.first

      unless active_version
        puts 'No versions found.'
        return
      end

      version_id = active_version['id']
      version_string = active_version.dig('attributes', 'versionString')
      state = active_version.dig('attributes', 'appStoreState')

      puts "\e[1mVersion:\e[0m #{version_string} (#{state})"
      puts

      locs = client.app_store_version_localizations(version_id: version_id)

      if @options.first
        # Show specific locale
        loc = locs.find { |l| l[:locale] == locale }
        unless loc
          puts "\e[31mLocale not found: #{locale}\e[0m"
          puts "Available: #{locs.map { |l| l[:locale] }.join(', ')}"
          return
        end

        puts "\e[1m#{loc[:locale]}:\e[0m"
        puts loc[:description] || '(no description)'
      else
        # Show all locales
        locs.each do |loc|
          puts "\e[1m#{loc[:locale]}:\e[0m"
          puts loc[:description] || '(no description)'
          puts
        end
      end
    end

    def cmd_update_description
      if @options.length < 2
        puts "\e[31mUsage: asc update-description <locale> \"Your app description\"\e[0m"
        puts 'Example: asc update-description en-US "My awesome app does amazing things..."'
        puts
        puts 'Tip: For multi-line descriptions, use a file:'
        puts '  asc update-description en-US "$(cat description.txt)"'
        exit 1
      end

      locale = @options[0]
      description = @options[1..].join(' ')

      versions = client.app_store_versions
      active_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'WAITING_FOR_REVIEW' }
      active_version ||= versions.find { |v| v.dig('attributes', 'appStoreState') == 'PREPARE_FOR_SUBMISSION' }

      unless active_version
        puts "\e[31mNo active version found to update.\e[0m"
        exit 1
      end

      version_id = active_version['id']
      locs = client.app_store_version_localizations(version_id: version_id)
      loc = locs.find { |l| l[:locale] == locale }

      unless loc
        puts "\e[31mLocale not found: #{locale}\e[0m"
        puts "Available: #{locs.map { |l| l[:locale] }.join(', ')}"
        exit 1
      end

      client.update_app_store_version_localization(localization_id: loc[:id], description: description)
      puts "\e[32mDescription updated!\e[0m"
      puts "  Version: #{active_version.dig('attributes', 'versionString')}"
      puts "  Locale: #{locale}"
      puts "  Description: #{description[0..100]}#{'...' if description.length > 100}"
    end

    def cmd_keywords
      locale = @options.first

      puts "\e[1mApp Keywords\e[0m"
      puts '=' * 50
      puts

      versions = client.app_store_versions
      active_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'WAITING_FOR_REVIEW' }
      active_version ||= versions.find { |v| v.dig('attributes', 'appStoreState') == 'PREPARE_FOR_SUBMISSION' }
      active_version ||= versions.first

      unless active_version
        puts 'No versions found.'
        return
      end

      version_id = active_version['id']
      version_string = active_version.dig('attributes', 'versionString')
      state = active_version.dig('attributes', 'appStoreState')

      puts "\e[1mVersion:\e[0m #{version_string} (#{state})"
      puts

      locs = client.app_store_version_localizations(version_id: version_id)

      if locale
        # Show specific locale
        loc = locs.find { |l| l[:locale] == locale }
        unless loc
          puts "\e[31mLocale not found: #{locale}\e[0m"
          puts "Available: #{locs.map { |l| l[:locale] }.join(', ')}"
          return
        end

        puts "\e[1m#{loc[:locale]}:\e[0m"
        puts loc[:keywords] || '(no keywords)'
      else
        # Show all locales
        locs.each do |loc|
          puts "\e[1m#{loc[:locale]}:\e[0m #{loc[:keywords] || '(no keywords)'}"
        end
      end
    end

    def cmd_update_keywords
      if @options.length < 2
        puts "\e[31mUsage: asc update-keywords <locale> \"keyword1, keyword2, keyword3\"\e[0m"
        puts 'Example: asc update-keywords en-US "productivity, notes, organizer"'
        puts
        puts 'Note: Keywords are comma-separated and have a 100 character limit.'
        exit 1
      end

      locale = @options[0]
      keywords = @options[1..].join(' ')

      if keywords.length > 100
        puts "\e[33mWarning: Keywords exceed 100 characters (#{keywords.length} chars)\e[0m"
      end

      versions = client.app_store_versions
      active_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'WAITING_FOR_REVIEW' }
      active_version ||= versions.find { |v| v.dig('attributes', 'appStoreState') == 'PREPARE_FOR_SUBMISSION' }

      unless active_version
        puts "\e[31mNo active version found to update.\e[0m"
        exit 1
      end

      version_id = active_version['id']
      locs = client.app_store_version_localizations(version_id: version_id)
      loc = locs.find { |l| l[:locale] == locale }

      unless loc
        puts "\e[31mLocale not found: #{locale}\e[0m"
        puts "Available: #{locs.map { |l| l[:locale] }.join(', ')}"
        exit 1
      end

      client.update_app_store_version_localization(localization_id: loc[:id], keywords: keywords)
      puts "\e[32mKeywords updated!\e[0m"
      puts "  Version: #{active_version.dig('attributes', 'versionString')}"
      puts "  Locale: #{locale}"
      puts "  Keywords: #{keywords}"
    end

    def cmd_urls
      locale = @options.first

      puts "\e[1mApp URLs\e[0m"
      puts '=' * 50
      puts

      versions = client.app_store_versions
      active_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'WAITING_FOR_REVIEW' }
      active_version ||= versions.find { |v| v.dig('attributes', 'appStoreState') == 'PREPARE_FOR_SUBMISSION' }
      active_version ||= versions.first

      unless active_version
        puts 'No versions found.'
        return
      end

      version_id = active_version['id']
      version_string = active_version.dig('attributes', 'versionString')
      state = active_version.dig('attributes', 'appStoreState')

      puts "\e[1mVersion:\e[0m #{version_string} (#{state})"
      puts

      locs = client.app_store_version_localizations(version_id: version_id)

      if locale
        # Show specific locale
        loc = locs.find { |l| l[:locale] == locale }
        unless loc
          puts "\e[31mLocale not found: #{locale}\e[0m"
          puts "Available: #{locs.map { |l| l[:locale] }.join(', ')}"
          return
        end

        puts "\e[1m#{loc[:locale]}:\e[0m"
        puts "  Marketing URL: #{loc[:marketing_url] || '(not set)'}"
        puts "  Support URL: #{loc[:support_url] || '(not set)'}"
      else
        # Show all locales
        locs.each do |loc|
          puts "\e[1m#{loc[:locale]}:\e[0m"
          puts "  Marketing URL: #{loc[:marketing_url] || '(not set)'}"
          puts "  Support URL: #{loc[:support_url] || '(not set)'}"
          puts
        end
      end
    end

    def cmd_update_marketing_url
      if @options.length < 2
        puts "\e[31mUsage: asc update-marketing-url <locale> <url>\e[0m"
        puts 'Example: asc update-marketing-url en-US https://example.com/app'
        exit 1
      end

      locale = @options[0]
      url = @options[1]

      versions = client.app_store_versions
      active_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'WAITING_FOR_REVIEW' }
      active_version ||= versions.find { |v| v.dig('attributes', 'appStoreState') == 'PREPARE_FOR_SUBMISSION' }

      unless active_version
        puts "\e[31mNo active version found to update.\e[0m"
        exit 1
      end

      version_id = active_version['id']
      locs = client.app_store_version_localizations(version_id: version_id)
      loc = locs.find { |l| l[:locale] == locale }

      unless loc
        puts "\e[31mLocale not found: #{locale}\e[0m"
        puts "Available: #{locs.map { |l| l[:locale] }.join(', ')}"
        exit 1
      end

      client.update_app_store_version_localization(localization_id: loc[:id], marketing_url: url)
      puts "\e[32mMarketing URL updated!\e[0m"
      puts "  Version: #{active_version.dig('attributes', 'versionString')}"
      puts "  Locale: #{locale}"
      puts "  Marketing URL: #{url}"
    end

    def cmd_update_support_url
      if @options.length < 2
        puts "\e[31mUsage: asc update-support-url <locale> <url>\e[0m"
        puts 'Example: asc update-support-url en-US https://example.com/support'
        exit 1
      end

      locale = @options[0]
      url = @options[1]

      versions = client.app_store_versions
      active_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'WAITING_FOR_REVIEW' }
      active_version ||= versions.find { |v| v.dig('attributes', 'appStoreState') == 'PREPARE_FOR_SUBMISSION' }

      unless active_version
        puts "\e[31mNo active version found to update.\e[0m"
        exit 1
      end

      version_id = active_version['id']
      locs = client.app_store_version_localizations(version_id: version_id)
      loc = locs.find { |l| l[:locale] == locale }

      unless loc
        puts "\e[31mLocale not found: #{locale}\e[0m"
        puts "Available: #{locs.map { |l| l[:locale] }.join(', ')}"
        exit 1
      end

      client.update_app_store_version_localization(localization_id: loc[:id], support_url: url)
      puts "\e[32mSupport URL updated!\e[0m"
      puts "  Version: #{active_version.dig('attributes', 'versionString')}"
      puts "  Locale: #{locale}"
      puts "  Support URL: #{url}"
    end

    def cmd_update_promotional_text
      if @options.length < 2
        puts "\e[31mUsage: asc update-promotional-text <locale> \"Your promotional text\"\e[0m"
        puts 'Example: asc update-promotional-text en-US "New feature: Dark mode!"'
        puts
        puts 'Note: Promotional text can be updated without submitting a new version.'
        exit 1
      end

      locale = @options[0]
      promotional_text = @options[1..].join(' ')

      versions = client.app_store_versions
      active_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'READY_FOR_SALE' }
      active_version ||= versions.find { |v| v.dig('attributes', 'appStoreState') == 'WAITING_FOR_REVIEW' }
      active_version ||= versions.find { |v| v.dig('attributes', 'appStoreState') == 'PREPARE_FOR_SUBMISSION' }

      unless active_version
        puts "\e[31mNo active version found to update.\e[0m"
        exit 1
      end

      version_id = active_version['id']
      locs = client.app_store_version_localizations(version_id: version_id)
      loc = locs.find { |l| l[:locale] == locale }

      unless loc
        puts "\e[31mLocale not found: #{locale}\e[0m"
        puts "Available: #{locs.map { |l| l[:locale] }.join(', ')}"
        exit 1
      end

      client.update_app_store_version_localization(localization_id: loc[:id], promotional_text: promotional_text)
      puts "\e[32mPromotional text updated!\e[0m"
      puts "  Version: #{active_version.dig('attributes', 'versionString')}"
      puts "  Locale: #{locale}"
      puts "  Promotional Text: #{promotional_text}"
    end

    def cmd_update_privacy_url
      if @options.length < 2
        puts "\e[31mUsage: asc update-privacy-url <locale> <url>\e[0m"
        puts 'Example: asc update-privacy-url en-US https://example.com/privacy'
        exit 1
      end

      locale = @options[0]
      url = @options[1]

      # Privacy URL is in appInfoLocalizations, not appStoreVersionLocalizations
      app_infos = client.app_info
      current_info = app_infos.find { |i| i[:state] != 'READY_FOR_DISTRIBUTION' }
      current_info ||= app_infos.first

      unless current_info
        puts "\e[31mNo app info found.\e[0m"
        exit 1
      end

      locs = client.app_info_localizations(app_info_id: current_info[:id])
      loc = locs.find { |l| l[:locale] == locale }

      unless loc
        puts "\e[31mLocale not found: #{locale}\e[0m"
        puts "Available: #{locs.map { |l| l[:locale] }.join(', ')}"
        exit 1
      end

      client.update_app_info_localization(localization_id: loc[:id], privacy_policy_url: url)
      puts "\e[32mPrivacy Policy URL updated!\e[0m"
      puts "  Locale: #{locale}"
      puts "  Privacy URL: #{url}"
    end

    # ─────────────────────────────────────────────────────────────────────────
    # In-App Purchase commands
    # ─────────────────────────────────────────────────────────────────────────

    def cmd_iaps
      puts "\e[1mIn-App Purchases\e[0m"
      puts '=' * 50
      puts

      iaps = client.in_app_purchases

      if iaps.empty?
        puts 'No in-app purchases found.'
        return
      end

      iaps.each do |iap|
        state_color = case iap[:state]
                      when 'APPROVED', 'READY_TO_SUBMIT' then "\e[32m"
                      when 'WAITING_FOR_REVIEW', 'IN_REVIEW' then "\e[33m"
                      when 'REJECTED', 'MISSING_METADATA' then "\e[31m"
                      else "\e[0m"
                      end

        puts "\e[1m#{iap[:name]}\e[0m (#{iap[:type]})"
        puts "  ID: #{iap[:id]}"
        puts "  Product ID: #{iap[:product_id]}"
        puts "  State: #{state_color}#{iap[:state]}\e[0m"
        puts "  Review Note: #{iap[:review_note] || '(none)'}"
        puts
      end
    end

    def cmd_iap_details
      puts "\e[1mIn-App Purchase Details\e[0m"
      puts '=' * 50
      puts

      iaps = client.in_app_purchases

      if iaps.empty?
        puts 'No in-app purchases found.'
        return
      end

      iaps.each do |iap|
        state_color = case iap[:state]
                      when 'APPROVED', 'READY_TO_SUBMIT' then "\e[32m"
                      when 'WAITING_FOR_REVIEW', 'IN_REVIEW' then "\e[33m"
                      when 'REJECTED', 'MISSING_METADATA' then "\e[31m"
                      else "\e[0m"
                      end

        puts "\e[1m#{iap[:name]}\e[0m (#{iap[:type]})"
        puts "  ID: #{iap[:id]}"
        puts "  Product ID: #{iap[:product_id]}"
        puts "  State: #{state_color}#{iap[:state]}\e[0m"
        puts "  Review Note: #{iap[:review_note] || '(none)'}"
        puts

        # Get localizations
        begin
          locs = client.in_app_purchase_localizations(iap_id: iap[:id])
          if locs.any?
            puts "  \e[1mLocalizations:\e[0m"
            locs.each do |loc|
              puts "    #{loc[:locale]}: #{loc[:name]}"
              puts "      ID: #{loc[:id]}"
              puts "      Description: #{loc[:description] || '(none)'}"
            end
          end
        rescue ApiError => e
          puts "  \e[33mCould not fetch localizations: #{e.message}\e[0m"
        end
        puts
      end
    end

    def cmd_update_iap_note
      if @options.length < 2
        puts "\e[31mUsage: asc update-iap-note <product_id> \"Review notes for Apple\"\e[0m"
        puts 'Example: asc update-iap-note com.example.app.coins.100 "This unlocks 100 coins for gameplay"'
        exit 1
      end

      product_id = @options[0]
      review_note = @options[1..].join(' ')

      iaps = client.in_app_purchases
      iap = iaps.find { |i| i[:product_id] == product_id }

      unless iap
        puts "\e[31mIn-App Purchase not found: #{product_id}\e[0m"
        exit 1
      end

      client.update_in_app_purchase(iap_id: iap[:id], review_note: review_note)
      puts "\e[32mUpdated IAP review note!\e[0m"
      puts "  Product: #{product_id}"
      puts "  Review Note: #{review_note}"
    end

    def cmd_update_iap_description
      if @options.length < 2
        puts "\e[31mUsage: asc update-iap-description <product_id> \"New description\"\e[0m"
        puts 'Example: asc update-iap-description com.example.app.coins.100 "Get 100 coins to use in-game"'
        exit 1
      end

      product_id = @options[0]
      description = @options[1..].join(' ')

      iaps = client.in_app_purchases
      iap = iaps.find { |i| i[:product_id] == product_id }

      unless iap
        puts "\e[31mIn-App Purchase not found: #{product_id}\e[0m"
        exit 1
      end

      locs = client.in_app_purchase_localizations(iap_id: iap[:id])
      en_loc = locs.find { |l| l[:locale] == 'en-US' }

      unless en_loc
        puts "\e[33mNo en-US localization found. Creating one...\e[0m"
        client.create_in_app_purchase_localization(
          iap_id: iap[:id],
          locale: 'en-US',
          name: iap[:name],
          description: description
        )
        puts "\e[32mCreated en-US localization with description.\e[0m"
        return
      end

      client.update_in_app_purchase_localization(localization_id: en_loc[:id], description: description)
      puts "\e[32mUpdated IAP description!\e[0m"
      puts "  Product: #{product_id}"
      puts "  Description: #{description}"
    end

    def cmd_submit_iap
      if @options.empty?
        puts "\e[31mUsage: asc submit-iap <product_id>\e[0m"
        puts 'Example: asc submit-iap com.example.app.coins.100'
        exit 1
      end

      product_id = @options[0]

      iaps = client.in_app_purchases
      iap = iaps.find { |i| i[:product_id] == product_id }

      unless iap
        puts "\e[31mIn-App Purchase not found: #{product_id}\e[0m"
        exit 1
      end

      print "Submit IAP '#{iap[:name]}' for review? (y/N): "
      confirm = $stdin.gets.chomp.downcase

      if confirm == 'y'
        client.submit_in_app_purchase(iap_id: iap[:id])
        puts "\e[32mIn-App Purchase submitted for review!\e[0m"
        puts "  Product: #{product_id}"
      else
        puts 'Cancelled.'
      end
    end

    # ─────────────────────────────────────────────────────────────────────────
    # Customer Review commands
    # ─────────────────────────────────────────────────────────────────────────

    def cmd_customer_reviews
      puts "\e[1mCustomer Reviews\e[0m"
      puts '=' * 50
      puts

      reviews = client.customer_reviews(limit: 20)

      if reviews.empty?
        puts 'No customer reviews found.'
        return
      end

      reviews.each_with_index do |review, i|
        stars = "\e[33m#{'★' * review[:rating]}#{'☆' * (5 - review[:rating])}\e[0m"
        created = review[:created_date] ? Time.parse(review[:created_date]).strftime('%Y-%m-%d') : 'N/A'

        puts "#{i + 1}. #{stars} (#{review[:territory]})"
        puts "   \e[1m#{review[:title]}\e[0m"
        puts "   #{review[:body][0..200]}#{'...' if review[:body].length > 200}" if review[:body]
        puts "   By: #{review[:reviewer_nickname]} on #{created}"
        puts "   ID: #{review[:id]}"

        # Check for existing response
        begin
          response = client.customer_review_response(review_id: review[:id])
          if response
            puts "   \e[32m↳ Response:\e[0m #{response[:response_body][0..100]}#{if response[:response_body].length > 100
                                                                                   '...'
                                                                                 end}"
          end
        rescue ApiError
          # No response or error fetching
        end
        puts
      end
    end

    def cmd_respond_review
      if @options.length < 2
        puts "\e[31mUsage: asc respond-review <review_id> \"Your response\"\e[0m"
        puts 'Example: asc respond-review abc123 "Thank you for your feedback!"'
        puts
        puts "Use 'asc customer-reviews' to find review IDs."
        exit 1
      end

      review_id = @options[0]
      response_body = @options[1..].join(' ')

      # Check if response already exists
      existing = client.customer_review_response(review_id: review_id)
      if existing
        puts "\e[33mThis review already has a response:\e[0m"
        puts "  #{existing[:response_body]}"
        puts
        print 'Delete existing response and create new one? (y/N): '
        confirm = $stdin.gets.chomp.downcase

        if confirm == 'y'
          client.delete_customer_review_response(response_id: existing[:id])
          puts "\e[32mDeleted existing response.\e[0m"
        else
          puts 'Cancelled.'
          return
        end
      end

      client.create_customer_review_response(review_id: review_id, response_body: response_body)
      puts "\e[32mResponse posted successfully!\e[0m"
      puts "  Review ID: #{review_id}"
      puts "  Response: #{response_body}"
    end

    # ─────────────────────────────────────────────────────────────────────────
    # Screenshot Upload commands
    # ─────────────────────────────────────────────────────────────────────────

    def cmd_upload_iap_screenshot
      if @options.length < 2
        puts "\e[31mUsage: asc upload-iap-screenshot <product_id> <file_path>\e[0m"
        puts 'Example: asc upload-iap-screenshot com.example.app.coins.100 ~/Desktop/screenshot.png'
        exit 1
      end

      product_id = @options[0]
      file_path = File.expand_path(@options[1])

      unless File.exist?(file_path)
        puts "\e[31mFile not found: #{file_path}\e[0m"
        exit 1
      end

      iaps = client.in_app_purchases
      iap = iaps.find { |i| i[:product_id] == product_id }

      unless iap
        puts "\e[31mIn-App Purchase not found: #{product_id}\e[0m"
        exit 1
      end

      # Check for existing screenshot
      existing = client.iap_review_screenshot(iap_id: iap[:id])
      if existing
        puts "\e[33mThis IAP already has a review screenshot.\e[0m"
        print 'Delete existing and upload new? (y/N): '
        confirm = $stdin.gets.chomp.downcase

        if confirm == 'y'
          client.delete_iap_review_screenshot(screenshot_id: existing[:id])
          puts "\e[32mDeleted existing screenshot.\e[0m"
        else
          puts 'Cancelled.'
          return
        end
      end

      puts 'Uploading screenshot...'
      result = client.upload_iap_review_screenshot(iap_id: iap[:id], file_path: file_path)

      puts "\e[32mScreenshot uploaded successfully!\e[0m"
      puts "  IAP: #{product_id}"
      puts "  File: #{File.basename(file_path)}"
      puts "  Screenshot ID: #{result['data']['id']}"
    end

    def cmd_delete_iap_screenshot
      if @options.empty?
        puts "\e[31mUsage: asc delete-iap-screenshot <product_id>\e[0m"
        puts 'Example: asc delete-iap-screenshot com.example.app.coins.100'
        exit 1
      end

      product_id = @options[0]

      iaps = client.in_app_purchases
      iap = iaps.find { |i| i[:product_id] == product_id }

      unless iap
        puts "\e[31mIn-App Purchase not found: #{product_id}\e[0m"
        exit 1
      end

      screenshot = client.iap_review_screenshot(iap_id: iap[:id])
      unless screenshot
        puts "\e[33mNo review screenshot found for this IAP.\e[0m"
        return
      end

      print "Delete review screenshot for '#{iap[:name]}'? (y/N): "
      confirm = $stdin.gets.chomp.downcase

      if confirm == 'y'
        client.delete_iap_review_screenshot(screenshot_id: screenshot[:id])
        puts "\e[32mScreenshot deleted.\e[0m"
      else
        puts 'Cancelled.'
      end
    end

    def cmd_screenshots
      puts "\e[1mApp Screenshots\e[0m"
      puts '=' * 50
      puts

      versions = client.app_store_versions
      active_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'PREPARE_FOR_SUBMISSION' }
      active_version ||= versions.first

      unless active_version
        puts 'No versions found.'
        return
      end

      version_id = active_version['id']
      version_string = active_version.dig('attributes', 'versionString')
      puts "\e[1mVersion:\e[0m #{version_string}"
      puts

      locs = client.app_store_version_localizations(version_id: version_id)

      locs.each do |loc|
        puts "\e[1m#{loc[:locale]}:\e[0m"

        begin
          sets = client.app_screenshot_sets(localization_id: loc[:id])

          if sets.empty?
            puts '  No screenshot sets found.'
          else
            sets.each do |set|
              puts "  \e[1m#{set[:screenshot_display_type]}:\e[0m"
              screenshots = client.app_screenshots(screenshot_set_id: set[:id])

              if screenshots.empty?
                puts '    (no screenshots)'
              else
                screenshots.each_with_index do |ss, idx|
                  state_color = ss[:upload_state] == 'COMPLETE' ? "\e[32m" : "\e[33m"
                  puts "    #{idx + 1}. #{ss[:file_name]} #{state_color}[#{ss[:upload_state]}]\e[0m"
                  puts "       ID: #{ss[:id]}"
                end
              end
            end
          end
        rescue ApiError => e
          puts "  \e[33mCould not fetch screenshots: #{e.message}\e[0m"
        end
        puts
      end
    end

    def cmd_upload_screenshot
      if @options.length < 3
        puts "\e[31mUsage: asc upload-screenshot <display_type> <locale> <file_path>\e[0m"
        puts 'Example: asc upload-screenshot APP_IPHONE_67 en-US ~/Desktop/screenshot.png'
        puts
        puts 'Common display types:'
        puts '  APP_IPHONE_67      - iPhone 6.7" (iPhone 14 Pro Max, 15 Pro Max)'
        puts '  APP_IPHONE_65      - iPhone 6.5" (iPhone 11 Pro Max, XS Max)'
        puts '  APP_IPHONE_55      - iPhone 5.5" (iPhone 8 Plus, 7 Plus, 6s Plus)'
        puts '  APP_IPAD_PRO_129   - iPad Pro 12.9"'
        puts '  APP_IPAD_PRO_11    - iPad Pro 11"'
        exit 1
      end

      display_type = @options[0]
      locale = @options[1]
      file_path = File.expand_path(@options[2])

      unless File.exist?(file_path)
        puts "\e[31mFile not found: #{file_path}\e[0m"
        exit 1
      end

      # Find the version and localization
      versions = client.app_store_versions
      active_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'PREPARE_FOR_SUBMISSION' }

      unless active_version
        puts "\e[31mNo version in PREPARE_FOR_SUBMISSION state.\e[0m"
        exit 1
      end

      version_id = active_version['id']
      locs = client.app_store_version_localizations(version_id: version_id)
      loc = locs.find { |l| l[:locale] == locale }

      unless loc
        puts "\e[31mLocalization not found: #{locale}\e[0m"
        puts "Available: #{locs.map { |l| l[:locale] }.join(', ')}"
        exit 1
      end

      # Find or create the screenshot set
      sets = client.app_screenshot_sets(localization_id: loc[:id])
      set = sets.find { |s| s[:screenshot_display_type] == display_type }

      unless set
        puts "Creating screenshot set for #{display_type}..."
        result = client.create_app_screenshot_set(localization_id: loc[:id], display_type: display_type)
        set = { id: result['data']['id'] }
      end

      puts 'Uploading screenshot...'
      result = client.upload_app_screenshot(screenshot_set_id: set[:id], file_path: file_path)

      puts "\e[32mScreenshot uploaded successfully!\e[0m"
      puts "  Display Type: #{display_type}"
      puts "  Locale: #{locale}"
      puts "  File: #{File.basename(file_path)}"
      puts "  Screenshot ID: #{result['data']['id']}"
    end

    # Batch upload screenshots from a directory
    # Directory structure should be: <display_type>/<filename>.png
    # Example: APP_IPHONE_67/screenshot1.png, APP_IPAD_PRO_129/screenshot1.png
    def cmd_upload_screenshots
      if @options.length < 2
        puts "\e[31mUsage: asc upload-screenshots <locale> <directory>\e[0m"
        puts 'Example: asc upload-screenshots en-US ~/Desktop/screenshots'
        puts
        puts 'Directory structure should contain folders named by display type:'
        puts '  screenshots/'
        puts '    APP_IPHONE_67/'
        puts '      screenshot1.png'
        puts '      screenshot2.png'
        puts '    APP_IPAD_PRO_129/'
        puts '      screenshot1.png'
        puts
        puts 'Supported display types:'
        puts '  APP_IPHONE_67      - iPhone 6.7" (1290 x 2796)'
        puts '  APP_IPHONE_65      - iPhone 6.5" (1242 x 2688)'
        puts '  APP_IPHONE_55      - iPhone 5.5" (1242 x 2208)'
        puts '  APP_IPAD_PRO_129   - iPad Pro 12.9" (2048 x 2732)'
        puts '  APP_IPAD_PRO_11    - iPad Pro 11" (1668 x 2388)'
        exit 1
      end

      locale = @options[0]
      directory = File.expand_path(@options[1])

      unless Dir.exist?(directory)
        puts "\e[31mDirectory not found: #{directory}\e[0m"
        exit 1
      end

      # Find the version and localization
      versions = client.app_store_versions
      active_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'PREPARE_FOR_SUBMISSION' }

      unless active_version
        puts "\e[31mNo version in PREPARE_FOR_SUBMISSION state.\e[0m"
        exit 1
      end

      version_id = active_version['id']
      locs = client.app_store_version_localizations(version_id: version_id)
      loc = locs.find { |l| l[:locale] == locale }

      unless loc
        puts "\e[31mLocalization not found: #{locale}\e[0m"
        puts "Available: #{locs.map { |l| l[:locale] }.join(', ')}"
        exit 1
      end

      display_types = %w[APP_IPHONE_67 APP_IPHONE_65 APP_IPHONE_55 APP_IPAD_PRO_129 APP_IPAD_PRO_11]
      uploaded = 0
      errors = []

      display_types.each do |display_type|
        type_dir = File.join(directory, display_type)
        next unless Dir.exist?(type_dir)

        # Get existing screenshot set or create one
        sets = client.app_screenshot_sets(localization_id: loc[:id])
        set = sets.find { |s| s[:screenshot_display_type] == display_type }

        unless set
          puts "Creating screenshot set for #{display_type}..."
          result = client.create_app_screenshot_set(localization_id: loc[:id], display_type: display_type)
          set = { id: result['data']['id'] }
        end

        # Upload each image file
        image_files = Dir.glob(File.join(type_dir, '*.{png,jpg,jpeg,PNG,JPG,JPEG}')).sort
        image_files.each do |file_path|
          puts "Uploading #{display_type}/#{File.basename(file_path)}..."
          begin
            client.upload_app_screenshot(screenshot_set_id: set[:id], file_path: file_path)
            uploaded += 1
          rescue StandardError => e
            errors << "#{display_type}/#{File.basename(file_path)}: #{e.message}"
          end
        end
      end

      puts
      puts "\e[32mUploaded #{uploaded} screenshot(s)\e[0m"
      if errors.any?
        puts "\e[31mErrors:\e[0m"
        errors.each { |e| puts "  - #{e}" }
      end
    end

    def cmd_delete_screenshot
      if @options.empty?
        puts "\e[31mUsage: asc delete-screenshot <screenshot_id>\e[0m"
        puts "Use 'asc screenshots' to find screenshot IDs."
        exit 1
      end

      screenshot_id = @options[0]

      print "Delete screenshot #{screenshot_id}? (y/N): "
      confirm = $stdin.gets.chomp.downcase

      if confirm == 'y'
        client.delete_app_screenshot(screenshot_id: screenshot_id)
        puts "\e[32mScreenshot deleted.\e[0m"
      else
        puts 'Cancelled.'
      end
    end

    # ─────────────────────────────────────────────────────────────────────────
    # Release Automation commands
    # ─────────────────────────────────────────────────────────────────────────

    def cmd_create_version
      if @options.empty?
        puts "\e[31mUsage: asc create-version <version_string> [release_type]\e[0m"
        puts 'Example: asc create-version 2.0.0'
        puts 'Example: asc create-version 2.0.0 MANUAL'
        puts
        puts 'Release types:'
        puts '  AFTER_APPROVAL  - Release immediately after approval (default)'
        puts '  MANUAL          - Hold for manual release after approval'
        puts '  SCHEDULED       - Release at a scheduled date'
        exit 1
      end

      version_string = @options[0]
      release_type = @options[1] || 'AFTER_APPROVAL'

      print "Create version #{version_string} with release type #{release_type}? (y/N): "
      confirm = $stdin.gets.chomp.downcase

      if confirm == 'y'
        result = client.create_app_store_version(
          version_string: version_string,
          release_type: release_type
        )

        puts "\e[32mVersion created successfully!\e[0m"
        puts "  Version: #{result[:version_string]}"
        puts "  ID: #{result[:id]}"
        puts "  State: #{result[:state]}"
        puts "  Release Type: #{result[:release_type]}"
      else
        puts 'Cancelled.'
      end
    end

    def cmd_release
      versions = client.app_store_versions
      pending = versions.find { |v| v.dig('attributes', 'appStoreState') == 'PENDING_DEVELOPER_RELEASE' }

      unless pending
        puts "\e[33mNo version pending developer release.\e[0m"
        puts
        puts 'Current versions:'
        versions.first(3).each do |v|
          puts "  #{v.dig('attributes', 'versionString')}: #{v.dig('attributes', 'appStoreState')}"
        end
        return
      end

      version_string = pending.dig('attributes', 'versionString')
      print "Release version #{version_string} to the App Store? (y/N): "
      confirm = $stdin.gets.chomp.downcase

      if confirm == 'y'
        client.release_version(version_id: pending['id'])
        puts "\e[32mVersion #{version_string} released!\e[0m"
      else
        puts 'Cancelled.'
      end
    end

    def cmd_phased_release
      puts "\e[1mPhased Release Status\e[0m"
      puts '=' * 50
      puts

      versions = client.app_store_versions
      # Find version that's either ready for sale or pending
      active_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'READY_FOR_SALE' }
      active_version ||= versions.find { |v| v.dig('attributes', 'appStoreState') == 'PENDING_DEVELOPER_RELEASE' }
      active_version ||= versions.find { |v| v.dig('attributes', 'appStoreState') == 'PREPARE_FOR_SUBMISSION' }

      unless active_version
        puts 'No active version found.'
        return
      end

      version_id = active_version['id']
      version_string = active_version.dig('attributes', 'versionString')
      state = active_version.dig('attributes', 'appStoreState')

      puts "\e[1mVersion:\e[0m #{version_string} (#{state})"
      puts

      phased = client.phased_release(version_id: version_id)

      if phased
        state_color = case phased[:state]
                      when 'ACTIVE' then "\e[32m"
                      when 'PAUSED' then "\e[33m"
                      when 'COMPLETE' then "\e[32m"
                      else "\e[0m"
                      end

        puts "\e[1mPhased Release:\e[0m"
        puts "  ID: #{phased[:id]}"
        puts "  State: #{state_color}#{phased[:state]}\e[0m"
        puts "  Day: #{phased[:current_day_number] || 'N/A'} of 7"
        puts "  Start Date: #{phased[:start_date] || 'Not started'}"

        # Show rollout percentage based on day
        if phased[:current_day_number]
          percentages = { 1 => 1, 2 => 2, 3 => 5, 4 => 10, 5 => 20, 6 => 50, 7 => 100 }
          pct = percentages[phased[:current_day_number]] || 0
          puts "  Rollout: #{pct}% of users"
        end
      else
        puts 'Phased release not enabled for this version.'
        puts
        puts "Use 'asc enable-phased-release' to enable gradual rollout."
      end
    end

    def cmd_enable_phased_release
      versions = client.app_store_versions
      active_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'PREPARE_FOR_SUBMISSION' }

      unless active_version
        puts "\e[31mNo version in PREPARE_FOR_SUBMISSION state.\e[0m"
        return
      end

      version_id = active_version['id']
      version_string = active_version.dig('attributes', 'versionString')

      # Check if already enabled
      existing = client.phased_release(version_id: version_id)
      if existing
        puts "\e[33mPhased release already enabled for version #{version_string}.\e[0m"
        puts "  State: #{existing[:state]}"
        return
      end

      print "Enable phased release for version #{version_string}? (y/N): "
      confirm = $stdin.gets.chomp.downcase

      if confirm == 'y'
        result = client.create_phased_release(version_id: version_id)
        puts "\e[32mPhased release enabled!\e[0m"
        puts "  Version: #{version_string}"
        puts "  Phased Release ID: #{result[:id]}"
        puts
        puts 'The release will roll out gradually over 7 days:'
        puts '  Day 1: 1%, Day 2: 2%, Day 3: 5%, Day 4: 10%'
        puts '  Day 5: 20%, Day 6: 50%, Day 7: 100%'
      else
        puts 'Cancelled.'
      end
    end

    def cmd_pause_release
      phased = find_active_phased_release
      return unless phased

      if phased[:state] == 'PAUSED'
        puts "\e[33mPhased release is already paused.\e[0m"
        return
      end

      print 'Pause the phased release? (y/N): '
      confirm = $stdin.gets.chomp.downcase

      if confirm == 'y'
        client.update_phased_release(phased_release_id: phased[:id], state: 'PAUSED')
        puts "\e[32mPhased release paused.\e[0m"
        puts 'Note: Users who already have the update will keep it.'
      else
        puts 'Cancelled.'
      end
    end

    def cmd_resume_release
      phased = find_active_phased_release
      return unless phased

      if phased[:state] == 'ACTIVE'
        puts "\e[33mPhased release is already active.\e[0m"
        return
      end

      print 'Resume the phased release? (y/N): '
      confirm = $stdin.gets.chomp.downcase

      if confirm == 'y'
        client.update_phased_release(phased_release_id: phased[:id], state: 'ACTIVE')
        puts "\e[32mPhased release resumed.\e[0m"
      else
        puts 'Cancelled.'
      end
    end

    def cmd_complete_release
      phased = find_active_phased_release
      return unless phased

      if phased[:state] == 'COMPLETE'
        puts "\e[33mPhased release is already complete.\e[0m"
        return
      end

      print "\e[33mRelease to ALL users immediately? (y/N): \e[0m"
      confirm = $stdin.gets.chomp.downcase

      if confirm == 'y'
        client.update_phased_release(phased_release_id: phased[:id], state: 'COMPLETE')
        puts "\e[32mReleased to all users!\e[0m"
      else
        puts 'Cancelled.'
      end
    end

    def cmd_pre_order
      puts "\e[1mPre-Order Status\e[0m"
      puts '=' * 50
      puts

      pre_order = client.pre_order

      if pre_order
        puts "\e[1mPre-Order Enabled\e[0m"
        puts "  ID: #{pre_order[:id]}"
        puts "  Release Date: #{pre_order[:app_release_date]}"
        puts "  Available Since: #{pre_order[:pre_order_available_date] || 'N/A'}"
      else
        puts 'Pre-order is not enabled for this app.'
        puts
        puts "Use 'asc enable-pre-order <date>' to enable pre-orders."
      end
    end

    def cmd_enable_pre_order
      if @options.empty?
        puts "\e[31mUsage: asc enable-pre-order <release_date>\e[0m"
        puts 'Example: asc enable-pre-order 2025-03-15'
        puts
        puts 'The release date must be in the future (format: YYYY-MM-DD)'
        exit 1
      end

      release_date = @options[0]

      # Validate date format
      unless release_date.match?(/^\d{4}-\d{2}-\d{2}$/)
        puts "\e[31mInvalid date format. Use YYYY-MM-DD\e[0m"
        exit 1
      end

      # Check if pre-order already exists
      existing = client.pre_order
      if existing
        puts "\e[33mPre-order already enabled.\e[0m"
        puts "  Current release date: #{existing[:app_release_date]}"
        print "Update to #{release_date}? (y/N): "
        confirm = $stdin.gets.chomp.downcase

        if confirm == 'y'
          client.update_pre_order(pre_order_id: existing[:id], app_release_date: release_date)
          puts "\e[32mPre-order date updated to #{release_date}.\e[0m"
        else
          puts 'Cancelled.'
        end
        return
      end

      print "Enable pre-order with release date #{release_date}? (y/N): "
      confirm = $stdin.gets.chomp.downcase

      if confirm == 'y'
        result = client.create_pre_order(app_release_date: release_date)
        puts "\e[32mPre-order enabled!\e[0m"
        puts "  Release Date: #{result[:app_release_date]}"
      else
        puts 'Cancelled.'
      end
    end

    def cmd_cancel_pre_order
      pre_order = client.pre_order

      unless pre_order
        puts "\e[33mPre-order is not enabled for this app.\e[0m"
        return
      end

      puts "Current pre-order release date: #{pre_order[:app_release_date]}"
      print "\e[33mCancel pre-order? This cannot be undone. (y/N): \e[0m"
      confirm = $stdin.gets.chomp.downcase

      if confirm == 'y'
        client.delete_pre_order(pre_order_id: pre_order[:id])
        puts "\e[32mPre-order cancelled.\e[0m"
      else
        puts 'Cancelled.'
      end
    end

    # ─────────────────────────────────────────────────────────────────────────
    # TestFlight commands
    # ─────────────────────────────────────────────────────────────────────────

    def cmd_testers
      puts "\e[1mBeta Testers\e[0m"
      puts '=' * 50
      puts

      testers = client.beta_testers
      if testers.empty?
        puts 'No beta testers found.'
        return
      end

      testers.each do |tester|
        state_color = case tester[:state]
                      when 'INSTALLED' then "\e[32m"
                      when 'INVITED' then "\e[33m"
                      else "\e[0m"
                      end

        puts "\e[1m#{tester[:first_name]} #{tester[:last_name]}\e[0m"
        puts "  ID: #{tester[:id]}"
        puts "  Email: #{tester[:email]}"
        puts "  State: #{state_color}#{tester[:state]}\e[0m"
        puts "  Invite Type: #{tester[:invite_type]}"
        puts
      end
    end

    def cmd_tester_groups
      puts "\e[1mBeta Groups\e[0m"
      puts '=' * 50
      puts

      groups = client.beta_groups
      if groups.empty?
        puts 'No beta groups found.'
        return
      end

      groups.each do |group|
        internal_label = group[:is_internal] ? "\e[33m[Internal]\e[0m" : ''

        puts "\e[1m#{group[:name]}\e[0m #{internal_label}"
        puts "  ID: #{group[:id]}"
        puts "  Public Link: #{group[:public_link_enabled] ? 'Enabled' : 'Disabled'}"
        puts "  Public URL: #{group[:public_link]}" if group[:public_link]
        puts "  Created: #{group[:created_date]}"
        puts
      end
    end

    def cmd_add_tester
      if @options.empty?
        puts "\e[31mUsage: asc add-tester <email> [first_name] [last_name] [group_id...]\e[0m"
        puts 'Example: asc add-tester test@example.com John Doe'
        puts 'Example: asc add-tester test@example.com John Doe group_id_1 group_id_2'
        exit 1
      end

      email = @options[0]
      first_name = @options[1]
      last_name = @options[2]
      group_ids = @options[3..] || []

      result = client.create_beta_tester(
        email: email,
        first_name: first_name,
        last_name: last_name,
        group_ids: group_ids
      )

      puts "\e[32mBeta tester added!\e[0m"
      puts "  Email: #{result[:email]}"
      puts "  ID: #{result[:id]}"
      puts "  State: #{result[:state]}"
    end

    def cmd_remove_tester
      if @options.empty?
        puts "\e[31mUsage: asc remove-tester <tester_id>\e[0m"
        puts "Use 'asc testers' to find tester IDs."
        exit 1
      end

      tester_id = @options[0]

      print "Remove beta tester #{tester_id}? (y/N): "
      confirm = $stdin.gets.chomp.downcase

      if confirm == 'y'
        client.delete_beta_tester(tester_id: tester_id)
        puts "\e[32mBeta tester removed.\e[0m"
      else
        puts 'Cancelled.'
      end
    end

    def cmd_create_group
      if @options.empty?
        puts "\e[31mUsage: asc create-group <name> [--public] [--limit N]\e[0m"
        puts 'Example: asc create-group "External Testers"'
        puts 'Example: asc create-group "Public Beta" --public --limit 1000'
        exit 1
      end

      name = @options[0]
      public_link = @options.include?('--public')
      limit_idx = @options.index('--limit')
      limit = limit_idx ? @options[limit_idx + 1]&.to_i : nil

      result = client.create_beta_group(
        name: name,
        public_link_enabled: public_link,
        public_link_limit: limit,
        public_link_limit_enabled: !limit.nil?
      )

      puts "\e[32mBeta group created!\e[0m"
      puts "  Name: #{result[:name]}"
      puts "  ID: #{result[:id]}"
      puts "  Public Link: #{result[:public_link]}" if result[:public_link]
    end

    def cmd_delete_group
      if @options.empty?
        puts "\e[31mUsage: asc delete-group <group_id>\e[0m"
        puts "Use 'asc tester-groups' to find group IDs."
        exit 1
      end

      group_id = @options[0]

      # Get group details for confirmation
      begin
        group = client.beta_group(group_id: group_id)
        puts "Group: #{group[:name]}"
      rescue ApiError
        puts "\e[31mGroup not found: #{group_id}\e[0m"
        exit 1
      end

      print "\e[33mDelete this beta group? (y/N): \e[0m"
      confirm = $stdin.gets.chomp.downcase

      if confirm == 'y'
        client.delete_beta_group(group_id: group_id)
        puts "\e[32mBeta group deleted.\e[0m"
      else
        puts 'Cancelled.'
      end
    end

    def cmd_group_testers
      if @options.empty?
        puts "\e[31mUsage: asc group-testers <group_id>\e[0m"
        puts "Use 'asc tester-groups' to find group IDs."
        exit 1
      end

      group_id = @options[0]

      # Get group name
      begin
        group = client.beta_group(group_id: group_id)
        puts "\e[1mTesters in '#{group[:name]}'\e[0m"
        puts '=' * 50
        puts
      rescue ApiError
        puts "\e[31mGroup not found: #{group_id}\e[0m"
        exit 1
      end

      testers = client.beta_group_testers(group_id: group_id)

      if testers.empty?
        puts 'No testers in this group.'
        return
      end

      testers.each do |tester|
        state_color = case tester[:state]
                      when 'INSTALLED' then "\e[32m"
                      when 'INVITED' then "\e[33m"
                      else "\e[0m"
                      end

        puts "#{tester[:first_name]} #{tester[:last_name]} <#{tester[:email]}>"
        puts "  ID: #{tester[:id]}"
        puts "  State: #{state_color}#{tester[:state]}\e[0m"
        puts
      end
    end

    def cmd_add_to_group
      if @options.length < 2
        puts "\e[31mUsage: asc add-to-group <group_id> <tester_id> [tester_id...]\e[0m"
        puts 'Example: asc add-to-group abc123 tester1 tester2 tester3'
        exit 1
      end

      group_id = @options[0]
      tester_ids = @options[1..]

      client.add_testers_to_group(group_id: group_id, tester_ids: tester_ids)
      puts "\e[32mAdded #{tester_ids.length} tester(s) to group.\e[0m"
    end

    def cmd_remove_from_group
      if @options.length < 2
        puts "\e[31mUsage: asc remove-from-group <group_id> <tester_id> [tester_id...]\e[0m"
        puts 'Example: asc remove-from-group abc123 tester1 tester2'
        exit 1
      end

      group_id = @options[0]
      tester_ids = @options[1..]

      print "Remove #{tester_ids.length} tester(s) from group? (y/N): "
      confirm = $stdin.gets.chomp.downcase

      if confirm == 'y'
        client.remove_testers_from_group(group_id: group_id, tester_ids: tester_ids)
        puts "\e[32mRemoved #{tester_ids.length} tester(s) from group.\e[0m"
      else
        puts 'Cancelled.'
      end
    end

    def cmd_testflight_builds
      puts "\e[1mTestFlight Builds\e[0m"
      puts '=' * 50
      puts

      builds = client.testflight_builds
      if builds.empty?
        puts 'No TestFlight builds found.'
        return
      end

      builds.each do |build|
        state_color = case build[:processing_state]
                      when 'VALID' then "\e[32m"
                      when 'PROCESSING' then "\e[33m"
                      when 'FAILED', 'INVALID' then "\e[31m"
                      else "\e[0m"
                      end

        beta_color = case build[:external_state]
                     when 'READY_FOR_BETA_TESTING' then "\e[32m"
                     when 'IN_BETA_REVIEW', 'WAITING_FOR_BETA_REVIEW' then "\e[33m"
                     when 'REJECTED' then "\e[31m"
                     else "\e[0m"
                     end

        uploaded = build[:uploaded_date] ? Time.parse(build[:uploaded_date]).strftime('%Y-%m-%d %H:%M') : 'N/A'

        puts "Build #{build[:version]}"
        puts "  ID: #{build[:id]}"
        puts "  Processing: #{state_color}#{build[:processing_state]}\e[0m"
        puts "  External Beta: #{beta_color}#{build[:external_state]}\e[0m"
        puts "  Internal: #{build[:uses_non_exempt_encryption] == false ? 'Ready' : 'Check encryption'}"
        puts "  Uploaded: #{uploaded}"
        puts
      end
    end

    def cmd_distribute_build
      if @options.length < 2
        puts "\e[31mUsage: asc distribute-build <build_id> <group_id> [group_id...]\e[0m"
        puts "Use 'asc testflight-builds' to find build IDs."
        puts "Use 'asc tester-groups' to find group IDs."
        exit 1
      end

      build_id = @options[0]
      group_ids = @options[1..]

      client.add_build_to_groups(build_id: build_id, group_ids: group_ids)
      puts "\e[32mBuild distributed to #{group_ids.length} group(s).\e[0m"
    end

    def cmd_remove_build
      if @options.length < 2
        puts "\e[31mUsage: asc remove-build <build_id> <group_id> [group_id...]\e[0m"
        puts 'Remove a build from beta groups.'
        exit 1
      end

      build_id = @options[0]
      group_ids = @options[1..]

      print "Remove build from #{group_ids.length} group(s)? (y/N): "
      confirm = $stdin.gets.chomp.downcase

      if confirm == 'y'
        client.remove_build_from_groups(build_id: build_id, group_ids: group_ids)
        puts "\e[32mBuild removed from #{group_ids.length} group(s).\e[0m"
      else
        puts 'Cancelled.'
      end
    end

    def cmd_beta_whats_new
      if @options.empty?
        puts "\e[31mUsage: asc beta-whats-new <build_id>\e[0m"
        puts 'Show What\'s New text for a TestFlight build.'
        exit 1
      end

      build_id = @options[0]

      puts "\e[1mBeta Build What's New\e[0m"
      puts '=' * 50
      puts

      localizations = client.beta_build_localizations(build_id: build_id)

      if localizations.empty?
        puts 'No What\'s New text set for this build.'
        puts
        puts "Use 'asc update-beta-whats-new' to add release notes."
        return
      end

      localizations.each do |loc|
        puts "\e[1m#{loc[:locale]}:\e[0m"
        puts "  ID: #{loc[:id]}"
        puts "  #{loc[:whats_new] || '(no text)'}"
        puts
      end
    end

    def cmd_update_beta_whats_new
      if @options.length < 2
        puts "\e[31mUsage: asc update-beta-whats-new <build_id> \"What's new text\"\e[0m"
        puts 'Example: asc update-beta-whats-new abc123 "Bug fixes and improvements"'
        exit 1
      end

      build_id = @options[0]
      whats_new = @options[1..].join(' ')

      # Check for existing localization
      localizations = client.beta_build_localizations(build_id: build_id)
      en_loc = localizations.find { |l| l[:locale] == 'en-US' }

      if en_loc
        client.update_beta_build_localization(localization_id: en_loc[:id], whats_new: whats_new)
        puts "\e[32mUpdated What's New text!\e[0m"
      else
        client.create_beta_build_localization(build_id: build_id, locale: 'en-US', whats_new: whats_new)
        puts "\e[32mCreated What's New text!\e[0m"
      end

      puts "  Build: #{build_id}"
      puts "  What's New: #{whats_new}"
    end

    def cmd_submit_beta_review
      if @options.empty?
        puts "\e[31mUsage: asc submit-beta-review <build_id>\e[0m"
        puts 'Submit a build for external TestFlight beta review.'
        exit 1
      end

      build_id = @options[0]

      # Check current status
      existing = client.beta_app_review_submission(build_id: build_id)
      if existing
        puts "\e[33mThis build already has a beta review submission.\e[0m"
        puts "  State: #{existing[:beta_review_state]}"
        return
      end

      print 'Submit build for external beta review? (y/N): '
      confirm = $stdin.gets.chomp.downcase

      if confirm == 'y'
        result = client.submit_for_beta_review(build_id: build_id)
        puts "\e[32mBuild submitted for beta review!\e[0m"
        puts "  Build: #{build_id}"
        puts "  State: #{result[:beta_review_state]}"
      else
        puts 'Cancelled.'
      end
    end

    def cmd_beta_review_status
      if @options.empty?
        puts "\e[31mUsage: asc beta-review-status <build_id>\e[0m"
        puts 'Check the beta review status of a build.'
        exit 1
      end

      build_id = @options[0]

      puts "\e[1mBeta Review Status\e[0m"
      puts '=' * 50
      puts

      submission = client.beta_app_review_submission(build_id: build_id)

      if submission
        state_color = case submission[:beta_review_state]
                      when 'APPROVED' then "\e[32m"
                      when 'IN_REVIEW', 'WAITING_FOR_REVIEW' then "\e[33m"
                      when 'REJECTED' then "\e[31m"
                      else "\e[0m"
                      end

        puts "Build: #{build_id}"
        puts "State: #{state_color}#{submission[:beta_review_state]}\e[0m"
        puts "Submitted: #{submission[:submitted_date] || 'N/A'}"
      else
        puts 'No beta review submission found for this build.'
        puts
        puts "Use 'asc submit-beta-review #{build_id}' to submit for review."
      end
    end

    # ─────────────────────────────────────────────────────────────────────────
    # App Administration commands
    # ─────────────────────────────────────────────────────────────────────────

    def cmd_app_info
      puts "\e[1mApp Information\e[0m"
      puts '=' * 50
      puts

      infos = client.app_info
      if infos.empty?
        puts 'No app info found.'
        return
      end

      info = infos.first
      puts "ID: #{info[:id]}"
      puts "State: #{info[:state]}"
      puts "Age Rating: #{info[:app_store_age_rating] || 'Not set'}"
      puts

      # Get localizations
      locs = client.app_info_localizations(app_info_id: info[:id])
      return unless locs.any?

      puts "\e[1mLocalizations:\e[0m"
      locs.each do |loc|
        puts "  \e[1m#{loc[:locale]}:\e[0m"
        puts "    Name: #{loc[:name]}"
        puts "    Subtitle: #{loc[:subtitle] || '(none)'}"
        puts "    Privacy Policy: #{loc[:privacy_policy_url] || '(none)'}"
        puts
      end
    end

    def cmd_age_rating
      puts "\e[1mAge Rating Declaration\e[0m"
      puts '=' * 50
      puts

      infos = client.app_info
      if infos.empty?
        puts 'No app info found.'
        return
      end

      info = infos.first
      rating = client.age_rating_declaration(app_info_id: info[:id])

      unless rating
        puts 'No age rating declaration found.'
        return
      end

      puts "ID: #{rating[:id]}"
      puts
      puts "\e[1mContent Ratings:\e[0m"
      puts "  Alcohol/Tobacco/Drugs: #{rating[:alcohol_tobacco_or_drug_use_or_references] || 'NONE'}"
      puts "  Gambling: #{rating[:gambling] || 'NONE'}"
      puts "  Gambling (Simulated): #{rating[:gambling_simulated] ? 'Yes' : 'No'}"
      puts "  Horror/Fear Themes: #{rating[:horror_or_fear_themes] || 'NONE'}"
      puts "  Mature/Suggestive: #{rating[:mature_or_suggestive_themes] || 'NONE'}"
      puts "  Medical Info: #{rating[:medical_or_treatment_information] || 'NONE'}"
      puts "  Profanity/Crude Humor: #{rating[:profanity_or_crude_humor] || 'NONE'}"
      puts "  Sexual Content: #{rating[:sexual_content_or_nudity] || 'NONE'}"
      puts "  Violence (Cartoon): #{rating[:violence_cartoon_or_fantasy] || 'NONE'}"
      puts "  Violence (Realistic): #{rating[:violence_realistic] || 'NONE'}"
      puts "  17+ Content: #{rating[:seventeen_plus] ? 'Yes' : 'No'}"
      puts "  Unrestricted Web Access: #{rating[:unrestricted_web_access] ? 'Yes' : 'No'}"
    end

    def cmd_categories
      puts "\e[1mAvailable App Categories\e[0m"
      puts '=' * 50
      puts

      platform = @options[0] || 'IOS'
      categories = client.available_categories(platform: platform)

      if categories.empty?
        puts "No categories found for #{platform}."
        return
      end

      categories.each do |cat|
        puts(cat[:id])
      end

      puts
      puts "Total: #{categories.length} categories"
    end

    def cmd_update_app_name
      if @options.empty?
        puts "\e[31mUsage: asc update-app-name \"New App Name\"\e[0m"
        exit 1
      end

      name = @options.join(' ')

      infos = client.app_info
      if infos.empty?
        puts "\e[31mNo app info found.\e[0m"
        exit 1
      end

      info = infos.first
      locs = client.app_info_localizations(app_info_id: info[:id])
      en_loc = locs.find { |l| l[:locale] == 'en-US' }

      unless en_loc
        puts "\e[31mNo en-US localization found.\e[0m"
        exit 1
      end

      client.update_app_info_localization(localization_id: en_loc[:id], name: name)
      puts "\e[32mApp name updated!\e[0m"
      puts "  New name: #{name}"
    end

    def cmd_update_subtitle
      if @options.empty?
        puts "\e[31mUsage: asc update-subtitle \"New Subtitle\"\e[0m"
        exit 1
      end

      subtitle = @options.join(' ')

      infos = client.app_info
      if infos.empty?
        puts "\e[31mNo app info found.\e[0m"
        exit 1
      end

      info = infos.first
      locs = client.app_info_localizations(app_info_id: info[:id])
      en_loc = locs.find { |l| l[:locale] == 'en-US' }

      unless en_loc
        puts "\e[31mNo en-US localization found.\e[0m"
        exit 1
      end

      client.update_app_info_localization(localization_id: en_loc[:id], subtitle: subtitle)
      puts "\e[32mSubtitle updated!\e[0m"
      puts "  New subtitle: #{subtitle}"
    end

    def cmd_availability
      puts "\e[1mApp Availability\e[0m"
      puts '=' * 50
      puts

      availability = client.app_availability
      unless availability
        puts 'No availability info found.'
        return
      end

      puts "ID: #{availability[:id]}"
      puts "Available in New Territories: #{availability[:available_in_new_territories] ? 'Yes' : 'No'}"
      puts
      puts "\e[1mAvailable Territories:\e[0m #{availability[:territories].length}"

      # Show first 20
      availability[:territories].first(20).each do |t|
        puts "  #{t[:id]} (#{t[:currency]})"
      end

      puts "  ... and #{availability[:territories].length - 20} more" if availability[:territories].length > 20
    end

    def cmd_territories
      puts "\e[1mAll Territories\e[0m"
      puts '=' * 50
      puts

      territories = client.territories
      territories.each do |t|
        puts "#{t[:id]}: #{t[:currency]}"
      end

      puts
      puts "Total: #{territories.length} territories"
    end

    def cmd_pricing
      puts "\e[1mApp Pricing\e[0m"
      puts '=' * 50
      puts

      schedule = client.app_price_schedule
      unless schedule
        puts 'No price schedule found.'
        return
      end

      puts "Base Territory: #{schedule[:base_territory]}"
      puts

      if schedule[:manual_prices].any?
        puts "\e[1mManual Prices:\e[0m"
        schedule[:manual_prices].each do |price|
          puts "  ID: #{price[:id]}"
          puts "    Start: #{price[:start_date] || 'Immediate'}"
          puts "    End: #{price[:end_date] || 'No end date'}"
        end
      end

      # Show price points for USA
      puts
      puts "\e[1mPrice Points (USA):\e[0m"
      points = client.app_price_points(territory: 'USA', limit: 20)
      points.each do |point|
        puts "  #{point[:id]}: $#{point[:customer_price]} (proceeds: $#{point[:proceeds]})"
      end
    end

    # ─────────────────────────────────────────────────────────────────────────
    # User Management commands
    # ─────────────────────────────────────────────────────────────────────────

    def cmd_users
      puts "\e[1mTeam Users\e[0m"
      puts '=' * 50
      puts

      users = client.users
      if users.empty?
        puts 'No users found.'
        return
      end

      users.each do |user|
        puts "\e[1m#{user[:first_name]} #{user[:last_name]}\e[0m"
        puts "  ID: #{user[:id]}"
        puts "  Email: #{user[:email]}"
        puts "  Username: #{user[:username]}"
        puts "  Roles: #{user[:roles]&.join(', ') || 'None'}"
        puts "  All Apps Visible: #{user[:all_apps_visible] ? 'Yes' : 'No'}"
        puts
      end
    end

    def cmd_invitations
      puts "\e[1mPending Invitations\e[0m"
      puts '=' * 50
      puts

      invitations = client.user_invitations
      if invitations.empty?
        puts 'No pending invitations.'
        return
      end

      invitations.each do |invite|
        expires = invite[:expiration_date] ? Time.parse(invite[:expiration_date]).strftime('%Y-%m-%d') : 'N/A'

        puts "\e[1m#{invite[:first_name]} #{invite[:last_name]}\e[0m"
        puts "  ID: #{invite[:id]}"
        puts "  Email: #{invite[:email]}"
        puts "  Roles: #{invite[:roles]&.join(', ') || 'None'}"
        puts "  Expires: #{expires}"
        puts
      end
    end

    def cmd_invite_user
      if @options.length < 4
        puts "\e[31mUsage: asc invite-user <email> <first_name> <last_name> <role> [role...]\e[0m"
        puts 'Example: asc invite-user jane@example.com Jane Doe DEVELOPER'
        puts 'Example: asc invite-user john@example.com John Smith APP_MANAGER MARKETING'
        puts
        puts 'Available roles:'
        puts '  ADMIN, FINANCE, ACCOUNT_HOLDER, SALES, MARKETING, APP_MANAGER,'
        puts '  DEVELOPER, ACCESS_TO_REPORTS, CUSTOMER_SUPPORT, CREATE_APPS'
        exit 1
      end

      email = @options[0]
      first_name = @options[1]
      last_name = @options[2]
      roles = @options[3..]

      result = client.create_user_invitation(
        email: email,
        first_name: first_name,
        last_name: last_name,
        roles: roles
      )

      puts "\e[32mInvitation sent!\e[0m"
      puts "  Email: #{result[:email]}"
      puts "  Roles: #{result[:roles]&.join(', ')}"
      puts "  Expires: #{result[:expiration_date]}"
    end

    def cmd_remove_user
      if @options.empty?
        puts "\e[31mUsage: asc remove-user <user_id>\e[0m"
        puts "Use 'asc users' to find user IDs."
        exit 1
      end

      user_id = @options[0]

      # Get user details for confirmation
      begin
        user = client.user(user_id: user_id)
        puts "User: #{user[:first_name]} #{user[:last_name]} (#{user[:email]})"
      rescue ApiError
        puts "\e[31mUser not found: #{user_id}\e[0m"
        exit 1
      end

      print "\e[33mRemove this user from the team? (y/N): \e[0m"
      confirm = $stdin.gets.chomp.downcase

      if confirm == 'y'
        client.delete_user(user_id: user_id)
        puts "\e[32mUser removed from team.\e[0m"
      else
        puts 'Cancelled.'
      end
    end

    def cmd_cancel_invitation
      if @options.empty?
        puts "\e[31mUsage: asc cancel-invitation <invitation_id>\e[0m"
        puts "Use 'asc invitations' to find invitation IDs."
        exit 1
      end

      invitation_id = @options[0]

      print "Cancel invitation #{invitation_id}? (y/N): "
      confirm = $stdin.gets.chomp.downcase

      if confirm == 'y'
        client.delete_user_invitation(invitation_id: invitation_id)
        puts "\e[32mInvitation cancelled.\e[0m"
      else
        puts 'Cancelled.'
      end
    end

    def cmd_privacy_labels
      puts "\e[1mApp Privacy Labels\e[0m"
      puts '=' * 50
      puts

      usages = client.app_data_usages
      if usages.empty?
        puts 'No privacy data usages declared.'
        puts
        puts 'Privacy labels must be configured in App Store Connect.'
        return
      end

      usages.each do |usage|
        puts "\e[1m#{usage[:category]}\e[0m"
        puts "  ID: #{usage[:id]}"
        puts "  Purposes: #{usage[:purposes]&.join(', ') || 'None'}"
        puts "  Data Protection: #{usage[:data_protection] || 'N/A'}"
        puts
      end
    end

    def find_active_phased_release
      versions = client.app_store_versions
      active_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'READY_FOR_SALE' }

      unless active_version
        puts "\e[31mNo version currently released.\e[0m"
        return nil
      end

      version_id = active_version['id']
      phased = client.phased_release(version_id: version_id)

      unless phased
        puts "\e[31mNo phased release found for current version.\e[0m"
        return nil
      end

      phased
    end

    public

    def cmd_help
      puts <<~HELP
        \e[1mApp Store Connect CLI\e[0m

        A command-line tool for checking and updating App Store Connect.

        \e[1mUSAGE:\e[0m
          asc <command> [options]

        \e[1mREAD COMMANDS:\e[0m
          status            Full app status summary (default)
          review            Check review submission status
          rejection         Show rejection details and status
          review-info       Show review contact info and notes
          subs              List subscription products
          sub-details       Detailed subscription info with localizations
          iaps              List in-app purchases
          iap-details       Detailed IAP info with localizations
          version-info      Show version localizations (description, what's new)
          screenshots       List app screenshots for current version
          builds            List recent builds
          apps              List all apps in your account
          ready             Check if ready for submission
          customer-reviews  List recent customer reviews

        \e[1mAPP METADATA:\e[0m
          description [locale]                  Show app description
          update-description <locale> "text"    Update app description
          keywords [locale]                     Show app keywords
          update-keywords <locale> "words"      Update keywords (100 char limit)
          urls [locale]                         Show marketing/support URLs
          update-marketing-url <locale> <url>   Update marketing URL
          update-support-url <locale> <url>     Update support URL
          update-promotional-text <locale> "text"  Update promotional text
          update-privacy-url <locale> <url>     Update privacy policy URL

        \e[1mWRITE COMMANDS (respond to Apple Review requests):\e[0m
          update-review-notes "notes"           Update notes for App Review
          update-review-contact [options]       Update App Review contact info
          update-demo-account [options]         Set demo account for App Review
          update-whats-new "text"               Update "What's New" release notes
          create-review-detail                  Create review detail for version
          update-sub-description <id> "desc"    Update subscription description
          update-sub-note <id> "note"           Update subscription review note
          update-iap-note <id> "note"           Update IAP review notes
          update-iap-description <id> "desc"    Update IAP description
          submit-iap <product_id>               Submit IAP for review
          respond-review <id> "response"        Respond to a customer review
          submit                                Submit version for App Review
          cancel-review                         Cancel pending review submission

        \e[1mSCREENSHOT COMMANDS:\e[0m
          upload-iap-screenshot <id> <file>     Upload IAP review screenshot
          delete-iap-screenshot <id>            Delete IAP review screenshot
          upload-screenshot <type> <locale> <file>  Upload app screenshot
          upload-screenshots <locale> <dir>    Batch upload from directory
          delete-screenshot <id>                Delete app screenshot

        \e[1mRELEASE AUTOMATION:\e[0m
          create-version <version> [type]       Create new app version
          release                               Release pending version to App Store
          phased-release                        Show phased release status
          enable-phased-release                 Enable 7-day gradual rollout
          pause-release                         Pause phased release
          resume-release                        Resume phased release
          complete-release                      Release to all users immediately
          pre-order                             Show pre-order status
          enable-pre-order <date>               Enable pre-orders (YYYY-MM-DD)
          cancel-pre-order                      Cancel pre-orders

        \e[1mTESTFLIGHT:\e[0m
          testers                               List beta testers
          tester-groups                         List beta groups
          add-tester <email> [name] [groups]    Add a beta tester
          remove-tester <tester_id>             Remove a beta tester
          create-group <name> [--public]        Create a beta group
          delete-group <group_id>               Delete a beta group
          group-testers <group_id>              List testers in a group
          add-to-group <group_id> <testers>     Add testers to a group
          remove-from-group <group> <testers>   Remove testers from group
          testflight-builds                     List TestFlight builds
          distribute-build <build> <groups>     Add build to groups
          remove-build <build> <groups>         Remove build from groups
          beta-whats-new <build_id>             Show What's New for build
          update-beta-whats-new <build> "text"  Update What's New text
          submit-beta-review <build_id>         Submit build for beta review
          beta-review-status <build_id>         Check beta review status

        \e[1mAPP ADMINISTRATION:\e[0m
          app-info                              Show app info and localizations
          age-rating                            Show age rating declaration
          categories [platform]                 List available categories
          update-app-name "name"                Update app name
          update-subtitle "subtitle"            Update app subtitle
          availability                          Show app territory availability
          territories                           List all territories
          pricing                               Show app pricing info
          privacy-labels                        Show app privacy declarations

        \e[1mUSER MANAGEMENT:\e[0m
          users                                 List team users
          invitations                           List pending invitations
          invite-user <email> <name> <roles>    Invite a new user
          remove-user <user_id>                 Remove user from team
          cancel-invitation <id>                Cancel pending invitation

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
          asc iap-details               # View IAP localizations
          asc customer-reviews          # View recent customer reviews

        \e[1mRESPONDING TO APPLE REVIEW:\e[0m
          # If Apple requests contact info (required before review notes):
          asc update-review-contact --first-name John --last-name Doe --email john@example.com --phone "+1234567890"

          # If your app requires sign-in, set demo account credentials:
          asc update-demo-account --username demo@example.com --password secret123 --required

          # If Apple requests updated reviewer notes:
          asc update-review-notes "Use demo account: test@example.com / password123"

          # If Apple requests updated release notes:
          asc update-whats-new "Fixed subscription flow issues"

          # If Apple requests subscription description update:
          asc update-sub-description com.example.app.plan.starter.monthly "Access to basic features"

          # If Apple requests IAP metadata update:
          asc update-iap-note com.example.app.coins.100 "Unlocks 100 coins for gameplay"
          asc update-iap-description com.example.app.coins.100 "Get 100 coins to use in-game"

          # Respond to customer reviews:
          asc customer-reviews
          asc respond-review abc123 "Thank you for your feedback!"

        \e[1mSCREENSHOT MANAGEMENT:\e[0m
          # View current screenshots:
          asc screenshots

          # Upload IAP review screenshot:
          asc upload-iap-screenshot com.example.app.coins.100 ~/Desktop/iap-screenshot.png

          # Upload app screenshot (iPhone 6.7"):
          asc upload-screenshot APP_IPHONE_67 en-US ~/Desktop/screenshot.png

          # Delete a screenshot:
          asc delete-screenshot abc123

        \e[1mRELEASE AUTOMATION:\e[0m
          # Create a new version:
          asc create-version 2.0.0
          asc create-version 2.0.0 MANUAL    # Hold for manual release

          # Enable phased rollout (gradual 7-day release):
          asc enable-phased-release

          # Control phased release:
          asc phased-release                 # Check status
          asc pause-release                  # Pause if issues found
          asc resume-release                 # Resume rollout
          asc complete-release               # Release to all users now

          # Manual release (for MANUAL release type):
          asc release

          # Pre-orders:
          asc enable-pre-order 2025-06-01
          asc pre-order                      # Check status
          asc cancel-pre-order

        \e[1mTESTFLIGHT AUTOMATION:\e[0m
          # Manage beta testers:
          asc testers                        # List all testers
          asc add-tester test@example.com John Doe
          asc remove-tester tester_id

          # Manage beta groups:
          asc tester-groups                  # List groups
          asc create-group "External Testers"
          asc create-group "Public Beta" --public --limit 1000
          asc group-testers group_id         # See testers in group
          asc add-to-group group_id tester1 tester2

          # Distribute builds:
          asc testflight-builds              # List builds
          asc distribute-build build_id group_id
          asc update-beta-whats-new build_id "Bug fixes"

          # External beta review:
          asc submit-beta-review build_id
          asc beta-review-status build_id

        \e[1mAPP ADMINISTRATION:\e[0m
          # View app info and settings:
          asc app-info                       # App name, subtitle, privacy URL
          asc age-rating                     # Content ratings
          asc categories                     # Available categories

          # Update app metadata:
          asc update-app-name "My Awesome App"
          asc update-subtitle "The best app ever"

          # View availability and pricing:
          asc availability                   # Where app is available
          asc territories                    # All territories
          asc pricing                        # Price points

          # Privacy labels:
          asc privacy-labels                 # Data usage declarations

        \e[1mUSER MANAGEMENT:\e[0m
          # View team:
          asc users                          # List all team members
          asc invitations                    # Pending invitations

          # Invite users:
          asc invite-user jane@example.com Jane Doe DEVELOPER
          asc invite-user john@example.com John Smith APP_MANAGER MARKETING

          # Manage users:
          asc remove-user user_id
          asc cancel-invitation invitation_id

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
          client.in_app_purchases
          client.customer_reviews
          client.update_in_app_purchase(iap_id: "123", review_note: "Note for reviewer")
          client.create_customer_review_response(review_id: "456", response_body: "Thanks!")

      HELP
    end
  end
end
