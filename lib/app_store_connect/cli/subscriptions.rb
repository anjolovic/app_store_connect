# frozen_string_literal: true

module AppStoreConnect
  class CLI
    # Subscription-related CLI commands
    module Subscriptions
      SUBSCRIPTION_PERIODS = %w[
        ONE_WEEK
        ONE_MONTH
        TWO_MONTHS
        THREE_MONTHS
        SIX_MONTHS
        ONE_YEAR
      ].freeze

      def cmd_subs
        cmd_subscriptions
      end

      def cmd_create_subscription
        cmd_create_sub
      end

      def cmd_create_sub
        if @options.empty?
          print_create_sub_usage
          exit 1
        end

        args = @options.dup
        product_id = nil
        name = nil
        period_input = nil
        group_id = nil
        group_name = nil
        create_group = false
        group_level = nil
        review_note = nil
        family_sharable = nil
        family_flag = nil
        locale = nil
        display_name = nil
        description = nil
        unknown = []

        while args.any?
          arg = args.shift
          case arg
          when '--product-id'
            product_id = args.shift
          when '--name'
            name = args.shift
          when '--period'
            period_input = args.shift
          when '--group-id'
            group_id = args.shift
          when '--group', '--group-name'
            group_name = args.shift
          when '--create-group'
            create_group = true
          when '--group-level'
            group_level = args.shift
          when '--review-note'
            review_note = args.shift
          when '--family-sharable'
            family_flag = true if family_flag.nil?
            if family_flag == false
              puts "\e[31mCannot use both --family-sharable and --not-family-sharable.\e[0m"
              exit 1
            end
            family_sharable = true
          when '--not-family-sharable', '--no-family-sharable'
            family_flag = false if family_flag.nil?
            if family_flag == true
              puts "\e[31mCannot use both --family-sharable and --not-family-sharable.\e[0m"
              exit 1
            end
            family_sharable = false
          when '--locale'
            locale = args.shift
          when '--display-name'
            display_name = args.shift
          when '--description'
            description = args.shift
          else
            if product_id.nil?
              product_id = arg
            elsif name.nil?
              name = arg
            elsif period_input.nil?
              period_input = arg
            else
              unknown << arg
            end
          end
        end

        if unknown.any?
          puts "\e[31mUnknown arguments: #{unknown.join(' ')}\e[0m"
          print_create_sub_usage
          exit 1
        end

        if product_id.nil? || name.nil? || period_input.nil?
          print_create_sub_usage
          exit 1
        end

        if product_id.match?(/\s/)
          puts "\e[31mProduct ID cannot contain spaces: #{product_id}\e[0m"
          exit 1
        end

        period = normalize_subscription_period(period_input)
        unless period
          puts "\e[31mInvalid subscription period: #{period_input}\e[0m"
          puts "Valid periods: #{SUBSCRIPTION_PERIODS.join(', ')}"
          puts "Examples: 1w, 1m, 2m, 3m, 6m, 1y"
          exit 1
        end

        if group_id && group_name
          puts "\e[31mUse either --group-id or --group, not both.\e[0m"
          exit 1
        end

        if group_level
          begin
            group_level = Integer(group_level, 10)
          rescue ArgumentError, TypeError
            puts "\e[31mGroup level must be an integer.\e[0m"
            exit 1
          end
          if group_level < 1
            puts "\e[31mGroup level must be 1 or higher.\e[0m"
            exit 1
          end
        end

        subs = client.subscriptions
        existing_sub = subs.find { |s| s.dig('attributes', 'productId') == product_id }
        if existing_sub
          puts "\e[31mSubscription already exists: #{product_id}\e[0m"
          puts "  Name: #{existing_sub.dig('attributes', 'name')}"
          puts "  State: #{existing_sub.dig('attributes', 'state')}"
          exit 1
        end

        iaps = client.in_app_purchases
        existing_iap = iaps.find { |i| i[:product_id] == product_id }
        if existing_iap
          puts "\e[31mProduct ID already used by an in-app purchase: #{product_id}\e[0m"
          puts "  IAP: #{existing_iap[:name]} (#{existing_iap[:type]})"
          exit 1
        end

        groups = client.subscription_groups
        group_display = nil
        create_group_needed = false

        if group_id
          group = groups.find { |g| g['id'] == group_id }
          unless group
            puts "\e[31mSubscription group not found: #{group_id}\e[0m"
            print_subscription_groups(groups)
            exit 1
          end
          group_display = subscription_group_label(group)
        elsif group_name
          group = groups.find { |g| g['id'] == group_name }
          group ||= groups.find { |g| subscription_group_name(g)&.casecmp?(group_name) }

          if group
            group_id = group['id']
            group_display = subscription_group_label(group)
          elsif create_group
            create_group_needed = true
            group_display = group_name
          else
            puts "\e[31mSubscription group not found: #{group_name}\e[0m"
            print_subscription_groups(groups)
            puts
            puts "Use --create-group --group \"#{group_name}\" to create it."
            exit 1
          end
        elsif groups.empty?
          puts "\e[31mNo subscription groups found.\e[0m"
          puts "Use --create-group --group \"Group Name\" to create one."
          exit 1
        elsif groups.length == 1
          group = groups.first
          group_id = group['id']
          group_display = subscription_group_label(group)
        else
          puts "\e[31mMultiple subscription groups found. Please specify one.\e[0m"
          print_subscription_groups(groups)
          exit 1
        end

        puts "\e[1mCreate Subscription\e[0m"
        puts '=' * 50
        puts "  Product ID: #{product_id}"
        puts "  Name: #{name}"
        puts "  Period: #{period}"
        group_suffix = group_id ? " (#{group_id})" : ''
        puts "  Group: #{group_display}#{group_suffix}"
        puts "  Group Level: #{group_level}" if group_level
        puts "  Family Sharing: #{family_sharable ? 'enabled' : 'disabled'}" unless family_sharable.nil?
        puts "  Review Note: #{review_note}" if review_note
        if display_name || description
          loc = locale || 'en-US'
          puts "  Localization: #{loc} (#{display_name || name})"
        end
        puts "  \e[33mThis will create a new subscription product.\e[0m"
        print "\e[33mProceed? (y/N): \e[0m"
        confirm = $stdin.gets&.strip&.downcase
        return unless confirm == 'y'

        created_group = nil
        if create_group_needed
          created_group = client.create_subscription_group(reference_name: group_name)
          group_id = created_group[:id]
          group_display = created_group[:reference_name] || group_name
        end

        subscription = client.create_subscription(
          subscription_group_id: group_id,
          name: name,
          product_id: product_id,
          subscription_period: period,
          family_sharable: family_sharable,
          review_note: review_note,
          group_level: group_level
        )

        puts "\e[32mSubscription created!\e[0m"
        puts "  ID: #{subscription[:id]}"
        puts "  Product ID: #{subscription[:product_id]}"
        puts "  Name: #{subscription[:name]}"
        puts "  State: #{subscription[:state]}" if subscription[:state]
        puts "  Group: #{group_display} (#{group_id})" if group_display
        puts "  Period: #{subscription[:subscription_period] || period}"
        puts "  Group Level: #{subscription[:group_level]}" if subscription[:group_level]

        if display_name || description
          loc = locale || 'en-US'
          loc_name = display_name || name
          begin
            client.create_subscription_localization(
              subscription_id: subscription[:id],
              locale: loc,
              name: loc_name,
              description: description
            )
            puts "  Localization: #{loc} (#{loc_name})"
          rescue ApiError => e
            puts "\e[33mWarning: Subscription created, but localization failed: #{e.message}\e[0m"
          end
        elsif locale
          puts "\e[33mLocale provided without --display-name/--description; skipping localization.\e[0m"
        end
      rescue ApiError => e
        puts "\e[31mError: #{e.message}\e[0m"
        if created_group
          puts "\e[33mNote: Subscription group '#{created_group[:reference_name]}' was created (ID: #{created_group[:id]}).\e[0m"
        end
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

      private

      def print_create_sub_usage
        puts "\e[31mUsage: asc create-sub <product_id> \"Reference Name\" <period> [options]\e[0m"
        puts 'Example: asc create-sub com.example.app.plan.monthly "Monthly Plan" 1m --group "Main Plans" --create-group'
        puts 'Example: asc create-sub com.example.app.plan.yearly "Yearly Plan" ONE_YEAR --group-id 12345'
        puts
        puts 'Periods: ONE_WEEK, ONE_MONTH, TWO_MONTHS, THREE_MONTHS, SIX_MONTHS, ONE_YEAR'
        puts 'Shorthand: 1w, 1m, 2m, 3m, 6m, 1y'
        puts
        puts 'Options:'
        puts '  --group <name|id>           Subscription group name or id'
        puts '  --group-id <id>             Subscription group id'
        puts '  --create-group              Create group if missing (requires --group)'
        puts '  --group-level <N>           Subscription group level (1 = lowest)'
        puts '  --review-note "text"        Review note for Apple'
        puts '  --family-sharable           Enable Family Sharing'
        puts '  --not-family-sharable       Disable Family Sharing'
        puts '  --locale <locale>           Localization locale (default: en-US)'
        puts '  --display-name "text"       Localized display name'
        puts '  --description "text"        Localized description'
      end

      def normalize_subscription_period(value)
        return nil if value.nil?

        normalized = value.strip.upcase.tr(' -', '_')
        normalized = normalized.gsub(/_+/, '_')
        return normalized if SUBSCRIPTION_PERIODS.include?(normalized)

        condensed = value.strip.downcase.gsub(/[^a-z0-9]/, '')
        map = {
          '1w' => 'ONE_WEEK',
          '1week' => 'ONE_WEEK',
          'week' => 'ONE_WEEK',
          '1m' => 'ONE_MONTH',
          '1month' => 'ONE_MONTH',
          'month' => 'ONE_MONTH',
          '2m' => 'TWO_MONTHS',
          '2month' => 'TWO_MONTHS',
          '2months' => 'TWO_MONTHS',
          '3m' => 'THREE_MONTHS',
          '3month' => 'THREE_MONTHS',
          '3months' => 'THREE_MONTHS',
          '6m' => 'SIX_MONTHS',
          '6month' => 'SIX_MONTHS',
          '6months' => 'SIX_MONTHS',
          '1y' => 'ONE_YEAR',
          '1year' => 'ONE_YEAR',
          'year' => 'ONE_YEAR'
        }
        map[condensed]
      end

      def subscription_group_name(group)
        group.dig('attributes', 'referenceName') || group.dig('attributes', 'name')
      end

      def subscription_group_label(group)
        subscription_group_name(group) || group['id']
      end

      def print_subscription_groups(groups)
        if groups.empty?
          puts 'No subscription groups found.'
          return
        end

        puts
        puts 'Available subscription groups:'
        groups.each do |group|
          puts "  - #{subscription_group_label(group)} (#{group['id']})"
        end
      end
    end
  end
end
