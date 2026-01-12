# frozen_string_literal: true

module AppStoreConnect
  class CLI
    # Subscription-related CLI commands
    module Subscriptions
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

      def cmd_delete_sub
        if @options.empty?
          puts "\e[31mUsage: asc delete-sub <product_id>\e[0m"
          puts 'Example: asc delete-sub com.example.app.plan.starter.monthly'
          puts
          puts "\e[33mNote: Can only delete subscriptions that have never been submitted for review.\e[0m"
          return
        end

        product_id = @options.first

        subs = client.subscriptions
        sub = subs.find { |s| s.dig('attributes', 'productId') == product_id }

        unless sub
          puts "\e[31mSubscription not found: #{product_id}\e[0m"
          puts
          puts 'Available subscriptions:'
          subs.each do |s|
            puts "  - #{s.dig('attributes', 'productId')}"
          end
          return
        end

        sub_name = sub.dig('attributes', 'name')
        sub_state = sub.dig('attributes', 'state')

        puts "Subscription: #{product_id}"
        puts "  Name: #{sub_name}"
        puts "  State: #{sub_state}"
        puts

        print "\e[33mAre you sure you want to delete this subscription? (yes/no): \e[0m"
        confirmation = $stdin.gets&.strip&.downcase

        unless confirmation == 'yes'
          puts 'Cancelled.'
          return
        end

        client.delete_subscription(subscription_id: sub['id'])
        puts "\e[32mSubscription deleted: #{product_id}\e[0m"
      rescue ApiError => e
        puts "\e[31mError: #{e.message}\e[0m"
        if e.message.include?('cannot be deleted') || e.message.include?('FORBIDDEN')
          puts
          puts "\e[33mNote: Subscriptions that have been submitted for review cannot be deleted.\e[0m"
          puts 'You can only delete subscriptions in draft state that were never submitted.'
        end
      end
    end
  end
end
