# frozen_string_literal: true

module AppStoreConnect
  class CLI
    # Release automation CLI commands
    module Releases
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
                        when 'ACTIVE', 'COMPLETE' then "\e[32m"
                        when 'PAUSED' then "\e[33m"
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
    end
  end
end
