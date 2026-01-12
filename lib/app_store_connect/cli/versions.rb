# frozen_string_literal: true

module AppStoreConnect
  class CLI
    # Version metadata CLI commands
    module Versions
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
          raise unless e.message.include?('cannot be edited') || e.message.include?('409')

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

        puts "\e[33mWarning: Keywords exceed 100 characters (#{keywords.length} chars)\e[0m" if keywords.length > 100

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
    end
  end
end
