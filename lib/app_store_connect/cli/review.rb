# frozen_string_literal: true

module AppStoreConnect
  class CLI
    # Review submission CLI commands
    module Review
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

      def cmd_content_rights
        puts "\e[1mContent Rights Declaration\e[0m"
        puts '=' * 50
        puts

        # Get the version that's being prepared or waiting for review
        versions = client.app_store_versions
        active_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'PREPARE_FOR_SUBMISSION' }
        active_version ||= versions.find { |v| v.dig('attributes', 'appStoreState') == 'WAITING_FOR_REVIEW' }

        unless active_version
          puts 'No active version found.'
          return
        end

        version_id = active_version['id']
        version_string = active_version.dig('attributes', 'versionString')
        puts "Version: #{version_string}"
        puts

        begin
          rights = client.content_rights_declaration(version_id: version_id)
          uses_content = rights[:uses_third_party_content]

          if uses_content.nil?
            puts "\e[33mContent rights not yet declared.\e[0m"
            puts
            puts 'Does your app contain, display, or access third-party content?'
            puts '  - User-generated content (photos, videos, posts)'
            puts '  - Content from social media, news feeds, or APIs'
            puts '  - Third-party images, audio, or video'
            puts
            puts 'Set with: asc set-content-rights yes   (uses third-party content)'
            puts '          asc set-content-rights no    (does NOT use third-party content)'
          elsif uses_content
            puts "\e[32mUses Third-Party Content: YES\e[0m"
            puts '  You have declared that your app uses third-party content'
            puts '  and you have the rights to use it.'
          else
            puts "\e[32mUses Third-Party Content: NO\e[0m"
            puts '  You have declared that your app does NOT use third-party content.'
          end
        rescue ApiError => e
          puts "\e[31mError: #{e.message}\e[0m"
        end
      end

      def cmd_set_content_rights
        if @options.empty?
          puts "\e[31mUsage: asc set-content-rights <yes|no>\e[0m"
          puts
          puts 'yes - App contains/displays/accesses third-party content'
          puts '      (and you have rights to use it)'
          puts 'no  - App does NOT contain third-party content'
          return
        end

        answer = @options.first.downcase
        unless %w[yes no true false 1 0].include?(answer)
          puts "\e[31mInvalid value. Use 'yes' or 'no'.\e[0m"
          return
        end

        uses_content = %w[yes true 1].include?(answer)

        # Get the version being prepared
        versions = client.app_store_versions
        active_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'PREPARE_FOR_SUBMISSION' }

        unless active_version
          puts "\e[31mNo version in PREPARE_FOR_SUBMISSION state.\e[0m"
          puts 'Content rights can only be set for versions being prepared for submission.'
          return
        end

        version_id = active_version['id']
        version_string = active_version.dig('attributes', 'versionString')

        puts "Setting content rights for version #{version_string}..."
        client.update_content_rights(version_id: version_id, uses_third_party_content: uses_content)

        if uses_content
          puts "\e[32mContent rights set: YES (uses third-party content)\e[0m"
          puts '  You are confirming you have the necessary rights.'
        else
          puts "\e[32mContent rights set: NO (does not use third-party content)\e[0m"
        end
      rescue ApiError => e
        puts "\e[31mError: #{e.message}\e[0m"
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
          client.create_app_store_review_detail(version_id: version_id, notes: notes)
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
          puts '  At least one option is required.'
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
          puts '  At least one option is required.'
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
    end
  end
end
