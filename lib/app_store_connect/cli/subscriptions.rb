# frozen_string_literal: true

require 'date'
require 'bigdecimal'
require 'fileutils'
require 'json'
require 'open3'
require 'yaml'

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
      INTRO_OFFER_MODES = %w[
        FREE_TRIAL
        PAY_AS_YOU_GO
        PAY_UP_FRONT
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
        dry_run = false
        json_output = json?
        no_confirm = false
        localizations_file = nil
        add_localizations = []
        price_point_id = nil
        price_territory = nil
        price_start_date = nil
        intro_offer_mode = nil
        intro_price_point_id = nil
        intro_duration_input = nil
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
          when '--yes', '--no-confirm'
            no_confirm = true
          when '--dry-run'
            dry_run = true
          when '--localizations-file'
            localizations_file = args.shift
          when '--add-localization'
            add_localizations << args.shift
          when '--price-point'
            price_point_id = args.shift
          when '--price-territory'
            price_territory = args.shift
          when '--price-start-date'
            price_start_date = args.shift
          when '--intro-offer'
            intro_offer_mode = args.shift
          when '--intro-price-point'
            intro_price_point_id = args.shift
          when '--intro-duration'
            intro_duration_input = args.shift
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

        if json_output && !no_confirm && !dry_run
          puts "\e[31m--json requires --yes or --no-confirm to avoid interactive prompts.\e[0m"
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

        if price_territory && price_point_id.nil?
          puts "\e[31m--price-territory requires --price-point.\e[0m"
          exit 1
        end

        if price_start_date
          begin
            price_start_date = Date.iso8601(price_start_date).strftime('%Y-%m-%d')
          rescue ArgumentError
            puts "\e[31mInvalid --price-start-date. Use YYYY-MM-DD.\e[0m"
            exit 1
          end
        end

        if intro_offer_mode
          intro_offer_mode = intro_offer_mode.strip.upcase.tr(' -', '_')
          unless INTRO_OFFER_MODES.include?(intro_offer_mode)
            puts "\e[31mInvalid --intro-offer. Use: #{INTRO_OFFER_MODES.join(', ')}\e[0m"
            exit 1
          end
          if intro_price_point_id.nil? || intro_duration_input.nil?
            puts "\e[31m--intro-offer requires --intro-price-point and --intro-duration.\e[0m"
            exit 1
          end
        elsif intro_price_point_id || intro_duration_input
          puts "\e[31m--intro-price-point/--intro-duration require --intro-offer.\e[0m"
          exit 1
        end

        intro_duration = nil
        if intro_duration_input
          intro_duration = normalize_subscription_period(intro_duration_input)
          unless intro_duration
            puts "\e[31mInvalid --intro-duration: #{intro_duration_input}\e[0m"
            puts "Valid durations: #{SUBSCRIPTION_PERIODS.join(', ')}"
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

        localizations = []
        if display_name || description
          localizations << {
            locale: locale || 'en-US',
            name: display_name || name,
            description: description
          }
        elsif locale
          puts "\e[33mLocale provided without --display-name/--description; skipping localization.\e[0m"
        end

        if add_localizations.any?
          add_localizations.each do |value|
            localizations << parse_localization_arg(value)
          end
        end

        if localizations_file
          localizations.concat(load_localizations_file(localizations_file))
        end

        normalize_localizations!(localizations) if localizations.any?

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
        localizations.each do |loc|
          puts "  Localization: #{loc[:locale]} (#{loc[:name]})"
        end
        puts "  Price Point: #{price_point_id}" if price_point_id
        puts "  Price Territory: #{price_territory}" if price_territory
        puts "  Price Start Date: #{price_start_date}" if price_start_date
        if intro_offer_mode
          puts "  Intro Offer: #{intro_offer_mode}"
          puts "  Intro Duration: #{intro_duration}"
          puts "  Intro Price Point: #{intro_price_point_id}"
        end
        puts "  \e[33mThis will create a new subscription product.\e[0m"
        if dry_run
          output_dry_run(
            json_output: json_output,
            product_id: product_id,
            name: name,
            period: period,
            group_id: group_id,
            group_display: group_display,
            create_group: create_group_needed,
            localizations: localizations,
            price_point_id: price_point_id,
            price_territory: price_territory,
            price_start_date: price_start_date,
            intro_offer_mode: intro_offer_mode,
            intro_duration: intro_duration,
            intro_price_point_id: intro_price_point_id
          )
          return
        end

        unless no_confirm
          print "\e[33mProceed? (y/N): \e[0m"
          confirm = $stdin.gets&.strip&.downcase
          return unless confirm == 'y'
        end

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

        price_result = nil
        if price_point_id
          if price_territory
            begin
              price_points = client.subscription_price_points_all(
                subscription_id: subscription[:id],
                territory: price_territory
              )
              price_point_ids = price_points.map { |p| p['id'] }
              unless price_point_ids.include?(price_point_id)
                puts "\e[33mWarning: Price point #{price_point_id} not found for territory #{price_territory}; skipping price creation.\e[0m"
                price_point_id = nil
              end
            rescue ApiError => e
              puts "\e[33mWarning: Could not validate price point: #{e.message}\e[0m"
            end
          end

          if price_point_id
            begin
              price_result = client.create_subscription_price(
                subscription_id: subscription[:id],
                subscription_price_point_id: price_point_id,
                start_date: price_start_date
              )
            rescue ApiError => e
              puts "\e[33mWarning: Subscription created, but price creation failed: #{e.message}\e[0m"
            end
          end
        end

        intro_result = nil
        if intro_offer_mode
          begin
            intro_result = client.create_subscription_introductory_offer(
              subscription_id: subscription[:id],
              offer_mode: intro_offer_mode,
              duration: intro_duration,
              subscription_price_point_id: intro_price_point_id
            )
          rescue ApiError => e
            puts "\e[33mWarning: Subscription created, but intro offer failed: #{e.message}\e[0m"
          end
        end

        localization_results = []
        localizations.each do |loc|
          begin
            result = client.create_subscription_localization(
              subscription_id: subscription[:id],
              locale: loc[:locale],
              name: loc[:name],
              description: loc[:description]
            )
            localization_results << {
              locale: loc[:locale],
              name: loc[:name],
              id: result.dig('data', 'id')
            }
          rescue ApiError => e
            puts "\e[33mWarning: Localization #{loc[:locale]} failed: #{e.message}\e[0m"
          end
        end

        if json_output
          puts JSON.pretty_generate(
            subscription: subscription.merge(group_id: group_id, group_name: group_display),
            price: price_result,
            introductory_offer: intro_result,
            localizations: localization_results
          )
        else
          puts "\e[32mSubscription created!\e[0m"
          puts "  ID: #{subscription[:id]}"
          puts "  Product ID: #{subscription[:product_id]}"
          puts "  Name: #{subscription[:name]}"
          puts "  State: #{subscription[:state]}" if subscription[:state]
          puts "  Group: #{group_display} (#{group_id})" if group_display
          puts "  Period: #{subscription[:subscription_period] || period}"
          puts "  Group Level: #{subscription[:group_level]}" if subscription[:group_level]
          if price_result
            puts "  Price: #{price_result[:price_point_id]} (start #{price_result[:start_date] || 'immediate'})"
          end
          if intro_result
            puts "  Intro Offer: #{intro_result[:offer_mode]} #{intro_result[:duration]}"
          end
          localization_results.each do |loc|
            puts "  Localization: #{loc[:locale]} (#{loc[:name]})"
          end
        end
      rescue ApiError => e
        puts "\e[31mError: #{e.message}\e[0m"
        if created_group
          puts "\e[33mNote: Subscription group '#{created_group[:reference_name]}' was created (ID: #{created_group[:id]}).\e[0m"
        end
      end

      def cmd_fix_sub_metadata
        if @options.empty?
          print_fix_sub_metadata_usage
          exit 1
        end

        args = @options.dup
        product_id = args.shift
        locale = nil
        display_name = nil
        description = nil
        dry_run = false
        json_output = json?
        no_confirm = false
        localizations_file = nil
        add_localizations = []
        price_point_id = nil
        price_territory = nil
        price_start_date = nil
        intro_offer_mode = nil
        intro_price_point_id = nil
        intro_duration_input = nil
        unknown = []

        while args.any?
          arg = args.shift
          case arg
          when '--locale'
            locale = args.shift
          when '--display-name'
            display_name = args.shift
          when '--description'
            description = args.shift
          when '--yes', '--no-confirm'
            no_confirm = true
          when '--dry-run'
            dry_run = true
          when '--localizations-file'
            localizations_file = args.shift
          when '--add-localization'
            add_localizations << args.shift
          when '--price-point'
            price_point_id = args.shift
          when '--price-territory'
            price_territory = args.shift
          when '--price-start-date'
            price_start_date = args.shift
          when '--intro-offer'
            intro_offer_mode = args.shift
          when '--intro-price-point'
            intro_price_point_id = args.shift
          when '--intro-duration'
            intro_duration_input = args.shift
          else
            unknown << arg
          end
        end

        if unknown.any?
          puts "\e[31mUnknown arguments: #{unknown.join(' ')}\e[0m"
          print_fix_sub_metadata_usage
          exit 1
        end

        if product_id.nil? || product_id.empty?
          print_fix_sub_metadata_usage
          exit 1
        end

        if json_output && !no_confirm && !dry_run
          puts "\e[31m--json requires --yes or --no-confirm to avoid interactive prompts.\e[0m"
          exit 1
        end

        if product_id.match?(/\s/)
          puts "\e[31mProduct ID cannot contain spaces: #{product_id}\e[0m"
          exit 1
        end

        if price_territory && price_point_id.nil?
          puts "\e[31m--price-territory requires --price-point.\e[0m"
          exit 1
        end

        if price_start_date
          begin
            price_start_date = Date.iso8601(price_start_date).strftime('%Y-%m-%d')
          rescue ArgumentError
            puts "\e[31mInvalid --price-start-date. Use YYYY-MM-DD.\e[0m"
            exit 1
          end
        end

        if intro_offer_mode
          intro_offer_mode = intro_offer_mode.strip.upcase.tr(' -', '_')
          unless INTRO_OFFER_MODES.include?(intro_offer_mode)
            puts "\e[31mInvalid --intro-offer. Use: #{INTRO_OFFER_MODES.join(', ')}\e[0m"
            exit 1
          end
          if intro_price_point_id.nil? || intro_duration_input.nil?
            puts "\e[31m--intro-offer requires --intro-price-point and --intro-duration.\e[0m"
            exit 1
          end
        elsif intro_price_point_id || intro_duration_input
          puts "\e[31m--intro-price-point/--intro-duration require --intro-offer.\e[0m"
          exit 1
        end

        intro_duration = nil
        if intro_duration_input
          intro_duration = normalize_subscription_period(intro_duration_input)
          unless intro_duration
            puts "\e[31mInvalid --intro-duration: #{intro_duration_input}\e[0m"
            puts "Valid durations: #{SUBSCRIPTION_PERIODS.join(', ')}"
            exit 1
          end
        end

        subs = client.subscriptions
        sub = subs.find { |s| s.dig('attributes', 'productId') == product_id }
        unless sub
          puts "\e[31mSubscription not found: #{product_id}\e[0m"
          puts
          puts 'Available subscriptions:'
          subs.each do |s|
            puts "  - #{s.dig('attributes', 'productId')}"
          end
          exit 1
        end

        sub_id = sub['id']
        default_name = sub.dig('attributes', 'name')

        localizations = []
        if display_name || description
          localizations << {
            locale: locale || 'en-US',
            name: display_name || default_name,
            description: description
          }
        elsif locale
          puts "\e[33mLocale provided without --display-name/--description; skipping localization.\e[0m"
        end

        if add_localizations.any?
          add_localizations.each do |value|
            localizations << parse_localization_arg(value)
          end
        end

        if localizations_file
          localizations.concat(load_localizations_file(localizations_file))
        end

        normalize_localizations!(localizations) if localizations.any?

        existing_localizations = client.subscription_localizations(subscription_id: sub_id)
        existing_locales = existing_localizations.map { |loc| loc[:locale].to_s.downcase }
        pending_localizations = localizations.reject do |loc|
          existing_locales.include?(loc[:locale].to_s.downcase)
        end

        puts "\e[1mFix Subscription Metadata\e[0m"
        puts '=' * 50
        puts "  Product ID: #{product_id}"
        puts "  Subscription ID: #{sub_id}"
        pending_localizations.each do |loc|
          puts "  Add Localization: #{loc[:locale]} (#{loc[:name]})"
        end
        (localizations - pending_localizations).each do |loc|
          puts "  Skip Localization: #{loc[:locale]} (already exists)"
        end
        puts "  Price Point: #{price_point_id}" if price_point_id
        puts "  Price Territory: #{price_territory}" if price_territory
        puts "  Price Start Date: #{price_start_date}" if price_start_date
        if intro_offer_mode
          puts "  Intro Offer: #{intro_offer_mode}"
          puts "  Intro Duration: #{intro_duration}"
          puts "  Intro Price Point: #{intro_price_point_id}"
        end

        if dry_run
          output_metadata_dry_run(
            json_output: json_output,
            product_id: product_id,
            subscription_id: sub_id,
            localizations: pending_localizations,
            skipped_localizations: localizations - pending_localizations,
            price_point_id: price_point_id,
            price_territory: price_territory,
            price_start_date: price_start_date,
            intro_offer_mode: intro_offer_mode,
            intro_duration: intro_duration,
            intro_price_point_id: intro_price_point_id
          )
          return
        end

        unless no_confirm
          print "\e[33mProceed? (y/N): \e[0m"
          confirm = $stdin.gets&.strip&.downcase
          return unless confirm == 'y'
        end

        localization_results = []
        pending_localizations.each do |loc|
          result = client.create_subscription_localization(
            subscription_id: sub_id,
            locale: loc[:locale],
            name: loc[:name],
            description: loc[:description]
          )
          localization_results << {
            locale: loc[:locale],
            name: loc[:name],
            id: result.dig('data', 'id')
          }
        rescue ApiError => e
          puts "\e[33mWarning: Localization #{loc[:locale]} failed: #{e.message}\e[0m"
        end

        price_result = nil
        if price_point_id
          if price_territory
            begin
              price_points = client.subscription_price_points_all(subscription_id: sub_id, territory: price_territory)
              price_point_ids = price_points.map { |p| p['id'] }
              unless price_point_ids.include?(price_point_id)
                puts "\e[33mWarning: Price point #{price_point_id} not found for territory #{price_territory}; skipping price creation.\e[0m"
                price_point_id = nil
              end
            rescue ApiError => e
              puts "\e[33mWarning: Could not validate price point: #{e.message}\e[0m"
            end
          end

          if price_point_id
            begin
              price_result = client.create_subscription_price(
                subscription_id: sub_id,
                subscription_price_point_id: price_point_id,
                start_date: price_start_date
              )
            rescue ApiError => e
              puts "\e[33mWarning: Price creation failed: #{e.message}\e[0m"
            end
          end
        end

        intro_result = nil
        if intro_offer_mode
          begin
            intro_result = client.create_subscription_introductory_offer(
              subscription_id: sub_id,
              offer_mode: intro_offer_mode,
              duration: intro_duration,
              subscription_price_point_id: intro_price_point_id
            )
          rescue ApiError => e
            puts "\e[33mWarning: Intro offer failed: #{e.message}\e[0m"
          end
        end

        if json_output
          puts JSON.pretty_generate(
            subscription: {
              id: sub_id,
              product_id: product_id
            },
            localizations: localization_results,
            price: price_result,
            introductory_offer: intro_result
          )
        else
          puts "\e[32mMetadata updated!\e[0m"
          localization_results.each do |loc|
            puts "  Localization: #{loc[:locale]} (#{loc[:name]})"
          end
          if price_result
            puts "  Price: #{price_result[:price_point_id]} (start #{price_result[:start_date] || 'immediate'})"
          end
          if intro_result
            puts "  Intro Offer: #{intro_result[:offer_mode]} #{intro_result[:duration]}"
          end
        end
      rescue ApiError => e
        puts "\e[31mError: #{e.message}\e[0m"
      end

      def cmd_sub_availability
        if @options.empty?
          puts "\e[31mUsage: asc sub-availability <product_id>\e[0m"
          exit 1
        end

        product_id = @options.first
        sub = find_subscription_by_product_id!(product_id)

        availability = client.subscription_availability(subscription_id: sub['id'])
        unless availability
          puts "\e[33mNo availability configured for #{product_id}.\e[0m"
          puts "Use 'asc set-sub-availability #{product_id} USA' to set territories."
          return
        end

        puts "\e[1mSubscription Availability\e[0m"
        puts '=' * 50
        puts "  Product ID: #{product_id}"
        puts "  Availability ID: #{availability[:id]}"
        if availability[:available_in_new_territories].nil?
          puts '  Available In New Territories: (not set)'
        else
          puts "  Available In New Territories: #{availability[:available_in_new_territories]}"
        end

        territories = availability[:territories] || []
        if territories.empty?
          puts '  Territories: (none)'
        else
          puts "  Territories (#{territories.length}):"
          territories.each do |territory|
            label = territory[:currency] ? "#{territory[:id]} (#{territory[:currency]})" : territory[:id]
            puts "    - #{label}"
          end
        end
      end

      def cmd_set_sub_availability
        if @options.empty?
          puts "\e[31mUsage: asc set-sub-availability <product_id> <territories...> [--all] [--available-in-new-territories true|false] [--yes] [--dry-run]\e[0m"
          puts 'Example: asc set-sub-availability com.example.app.plan.monthly USA CAN GBR --available-in-new-territories true'
          puts 'Example: asc set-sub-availability com.example.app.plan.monthly --all --available-in-new-territories false'
          exit 1
        end

        args = @options.dup
        product_id = args.shift
        all = args.delete('--all')
        dry_run = args.delete('--dry-run')
        no_confirm = args.delete('--yes') || args.delete('--no-confirm')
        available_in_new = nil

        parsed = []
        while args.any?
          arg = args.shift
          case arg
          when '--available-in-new-territories', '--new-territories'
            available_in_new = parse_bool(args.shift)
            if available_in_new.nil?
              puts "\e[31m--available-in-new-territories must be true/false.\e[0m"
              exit 1
            end
          else
            parsed << arg
          end
        end

        territories = parsed.map { |t| t.strip.upcase }.reject(&:empty?)

        if !all && territories.empty?
          puts "\e[31mPlease specify territories or use --all.\e[0m"
          exit 1
        end

        sub = find_subscription_by_product_id!(product_id)

        territory_ids =
          if all
            client.territories.map { |t| t[:id] }
          else
            territories
          end

        availability = client.subscription_availability(subscription_id: sub['id'])
        availability_id = availability&.dig(:id)

        puts "\e[1mSet Subscription Availability\e[0m"
        puts '=' * 50
        puts "  Product ID: #{product_id}"
        puts "  Territories: #{territory_ids.join(', ')}"
        puts "  Available In New Territories: #{available_in_new}" unless available_in_new.nil?

        if dry_run
          puts "\e[33mDry run: no changes made.\e[0m"
          return
        end

        unless no_confirm
          print "\e[33mProceed? (y/N): \e[0m"
          confirm = $stdin.gets&.strip&.downcase
          return unless confirm == 'y'
        end

        if availability_id
          if !available_in_new.nil?
            client.update_subscription_availability_attributes(
              availability_id: availability_id,
              available_in_new_territories: available_in_new
            )
          end
          client.update_subscription_availability(
            availability_id: availability_id,
            territory_ids: territory_ids
          )
        else
          if available_in_new.nil?
            puts "\e[31mMissing --available-in-new-territories when creating availability.\e[0m"
            exit 1
          end
          client.create_subscription_availability(
            subscription_id: sub['id'],
            territory_ids: territory_ids,
            available_in_new_territories: available_in_new
          )
        end

        puts "\e[32mAvailability updated!\e[0m"
      rescue ApiError => e
        puts "\e[31mError: #{e.message}\e[0m"
      end

      def cmd_sub_price_points
        if @options.empty?
          puts "\e[31mUsage: asc sub-price-points <product_id> [territory] [--limit N] [--all] [--search-price VALUE]\e[0m"
          puts 'Example: asc sub-price-points com.example.app.plan.monthly USA --all'
          puts 'Example: asc sub-price-points com.example.app.plan.monthly USA --search-price 599'
          exit 1
        end

        args = @options.dup
        product_id = args.shift
        territory = 'USA'
        limit = 200
        cursor = nil
        all = false
        search_price = nil

        while args.any?
          arg = args.shift
          case arg
          when '--limit'
            raw = args.shift
            if raw.nil?
              puts "\e[31m--limit requires a value.\e[0m"
              exit 1
            end

            begin
              limit = Integer(raw, 10)
            rescue ArgumentError, TypeError
              puts "\e[31m--limit must be an integer.\e[0m"
              exit 1
            end

            if limit <= 0
              puts "\e[31m--limit must be greater than 0.\e[0m"
              exit 1
            end
          when '--after'
            cursor = args.shift
            if cursor.nil? || cursor.strip.empty?
              puts "\e[31m--after requires a value.\e[0m"
              exit 1
            end
          when '--all'
            all = true
          when '--search-price'
            search_price = args.shift
            if search_price.nil? || search_price.strip.empty?
              puts "\e[31m--search-price requires a value.\e[0m"
              exit 1
            end
          else
            if territory == 'USA'
              territory = arg
            else
              puts "\e[31mUnknown argument: #{arg}\e[0m"
              exit 1
            end
          end
        end

        all = true if search_price && !all && cursor.nil? && limit == 200

        sub = find_subscription_by_product_id!(product_id)

        points = []
        max_limit = 2000

        if cursor
          puts "\e[33mWarning: --after is not supported for subscription price points; ignoring.\e[0m"
          cursor = nil
        end

        if all || search_price
          limit = [limit, max_limit].min
          limit = max_limit if limit < max_limit

          points = client.subscription_price_points_all(
            subscription_id: sub['id'],
            territory: territory,
            limit: limit
          )
        else
          page = client.subscription_price_points_page(
            subscription_id: sub['id'],
            territory: territory,
            limit: limit,
            cursor: cursor
          )
          points = page[:data]
        end

        if search_price
          search_values = search_price.to_s.split('/').map(&:strip).reject(&:empty?)
          normalized_targets = search_values.map { |value| normalize_price_value(value) }.compact

          if normalized_targets.empty?
            puts "\e[31mInvalid --search-price value.\e[0m"
            exit 1
          end

          points = points.select do |point|
            attrs = point['attributes'] || {}
            price = attrs['customerPrice'] || attrs['price']
            normalized = normalize_price_value(price)
            normalized && normalized_targets.include?(normalized)
          end
        end

        puts "\e[1mSubscription Price Points (#{territory})\e[0m"
        puts '=' * 50

        if points.empty?
          puts 'No price points found.'
        else
          points.each do |point|
            attrs = point['attributes'] || {}
            price = attrs['customerPrice'] || attrs['price']
            proceeds = attrs['proceeds']
            label = [price, proceeds].compact.join(' / ')
            label = "(#{label})" unless label.empty?
            puts "  - #{point['id']} #{label}"
          end
        end

      rescue ApiError => e
        puts "\e[31mError: #{e.message}\e[0m"
      end

      def cmd_sub_prices
        if @options.empty?
          puts "\e[31mUsage: asc sub-prices <product_id>\e[0m"
          exit 1
        end

        product_id = @options.first
        sub = find_subscription_by_product_id!(product_id)
        prices = client.subscription_prices(subscription_id: sub['id'])

        puts "\e[1mSubscription Price Schedule\e[0m"
        puts '=' * 50

        if prices.empty?
          puts 'No subscription prices configured.'
          return
        end

        prices.sort_by { |p| p[:start_date] || '' }.each do |price|
          start_date = price[:start_date] || 'immediate'
          preserved = price[:preserved] ? 'preserved' : 'standard'
          puts "  - #{price[:price_point_id]} (start #{start_date}, #{preserved})"
        end
      rescue ApiError => e
        puts "\e[31mError: #{e.message}\e[0m"
      end

      def cmd_add_sub_price
        if @options.empty?
          puts "\e[31mUsage: asc add-sub-price <product_id> <price_point_id> [--start-date YYYY-MM-DD]\e[0m"
          exit 1
        end

        args = @options.dup
        product_id = args.shift
        price_point_id = args.shift
        start_date = nil

        while args.any?
          arg = args.shift
          case arg
          when '--start-date'
            start_date = args.shift
          else
            puts "\e[31mUnknown argument: #{arg}\e[0m"
            exit 1
          end
        end

        if start_date
          begin
            start_date = Date.iso8601(start_date).strftime('%Y-%m-%d')
          rescue ArgumentError
            puts "\e[31mInvalid --start-date. Use YYYY-MM-DD.\e[0m"
            exit 1
          end
        end

        sub = find_subscription_by_product_id!(product_id)
        result = client.create_subscription_price(
          subscription_id: sub['id'],
          subscription_price_point_id: price_point_id,
          start_date: start_date
        )

        puts "\e[32mSubscription price added!\e[0m"
        puts "  ID: #{result[:id]}"
        puts "  Price Point: #{result[:price_point_id]}"
        puts "  Start Date: #{result[:start_date] || 'immediate'}"
      rescue ApiError => e
        puts "\e[31mError: #{e.message}\e[0m"
      end

      def cmd_sub_image
        if @options.empty?
          puts "\e[31mUsage: asc sub-image <product_id>\e[0m"
          exit 1
        end

        product_id = @options.first
        sub = find_subscription_by_product_id!(product_id)
        images = client.subscription_images(subscription_id: sub['id'])

        if images.empty?
          puts "\e[33mNo subscription images found for #{product_id}.\e[0m"
          return
        end

        puts "\e[1mSubscription Images\e[0m"
        puts '=' * 50
        images.each do |image|
          puts "  ID: #{image[:id]}"
          puts "    File: #{image[:file_name]} (#{image[:file_size]} bytes)"
          puts "    State: #{image[:upload_state]}"
        end
      rescue ApiError => e
        puts "\e[31mError: #{e.message}\e[0m"
      end

      def cmd_upload_sub_image
        if @options.length < 2
          puts "\e[31mUsage: asc upload-sub-image <product_id> <file_path>\e[0m"
          exit 1
        end

        product_id = @options[0]
        file_path = @options[1]
        sub = find_subscription_by_product_id!(product_id)

        images = client.subscription_images(subscription_id: sub['id'])
        if images.any?
          puts "\e[33mThis subscription already has #{images.length} image(s).\e[0m"
          print "\e[33mReplace existing image(s)? (y/N): \e[0m"
          confirm = $stdin.gets&.strip&.downcase
          return unless confirm == 'y'

          images.each { |image| client.delete_subscription_image(image_id: image[:id]) }
        end

        puts 'Uploading subscription image...'
        result = client.upload_subscription_image(subscription_id: sub['id'], file_path: file_path)
        puts "\e[32mSubscription image uploaded!\e[0m"
        puts "  Image ID: #{result['data']['id']}"
      rescue ApiError => e
        puts "\e[31mError: #{e.message}\e[0m"
      end

      def cmd_delete_sub_image
        if @options.empty?
          puts "\e[31mUsage: asc delete-sub-image <product_id>\e[0m"
          exit 1
        end

        product_id = @options.first
        sub = find_subscription_by_product_id!(product_id)
        images = client.subscription_images(subscription_id: sub['id'])

        if images.empty?
          puts "\e[33mNo subscription images found for #{product_id}.\e[0m"
          return
        end

        print "\e[33mDelete #{images.length} image(s) for #{product_id}? (y/N): \e[0m"
        confirm = $stdin.gets&.strip&.downcase
        return unless confirm == 'y'

        images.each { |image| client.delete_subscription_image(image_id: image[:id]) }
        puts "\e[32mSubscription images deleted.\e[0m"
      rescue ApiError => e
        puts "\e[31mError: #{e.message}\e[0m"
      end

      def cmd_sub_review_screenshot
        if @options.empty?
          puts "\e[31mUsage: asc sub-review-screenshot <product_id>\e[0m"
          exit 1
        end

        product_id = @options.first
        sub = find_subscription_by_product_id!(product_id)
        screenshot = client.subscription_review_screenshot(subscription_id: sub['id'])

        unless screenshot
          puts "\e[33mNo review screenshot found for #{product_id}.\e[0m"
          return
        end

        puts "\e[1mSubscription Review Screenshot\e[0m"
        puts '=' * 50
        puts "  ID: #{screenshot[:id]}"
        puts "  File: #{screenshot[:file_name]} (#{screenshot[:file_size]} bytes)"
        puts "  State: #{screenshot[:upload_state]}"
      rescue ApiError => e
        puts "\e[31mError: #{e.message}\e[0m"
      end

      def cmd_upload_sub_review_screenshot
        if @options.empty?
          puts "\e[31mUsage: asc upload-sub-review-screenshot <product_id> [file_path] [--capture] [--output PATH] [--simulator-id ID|--simulator-name NAME]\e[0m"
          puts 'Example: asc upload-sub-review-screenshot com.example.app.plan.monthly ./paywall.png'
          puts 'Example: asc upload-sub-review-screenshot com.example.app.plan.monthly --capture --output ./subscription-review.png'
          exit 1
        end

        args = @options.dup
        product_id = args.shift
        file_path = nil
        capture = false
        output_path = nil
        simulator_id = nil
        simulator_name = nil

        while args.any?
          arg = args.shift
          case arg
          when '--capture'
            capture = true
          when '--output'
            output_path = args.shift
          when '--simulator-id'
            simulator_id = args.shift
          when '--simulator-name'
            simulator_name = args.shift
          else
            if file_path.nil?
              file_path = arg
            else
              puts "\e[31mUnknown argument: #{arg}\e[0m"
              exit 1
            end
          end
        end

        if output_path && !capture
          puts "\e[31m--output requires --capture.\e[0m"
          exit 1
        end

        if (simulator_id || simulator_name) && !capture
          puts "\e[31m--simulator-id/--simulator-name require --capture.\e[0m"
          exit 1
        end

        if simulator_id && simulator_name
          puts "\e[31mPlease provide only one of --simulator-id or --simulator-name.\e[0m"
          exit 1
        end

        if capture
          file_path = output_path || file_path || 'subscription-review.png'
          begin
            capture_simulator_screenshot(
              file_path,
              simulator_id: simulator_id,
              simulator_name: simulator_name
            )
          rescue StandardError => e
            puts "\e[31mScreenshot capture failed: #{e.message}\e[0m"
            exit 1
          end
        end

        if file_path.nil? || file_path.strip.empty?
          puts "\e[31mMissing file path. Provide a file path or use --capture.\e[0m"
          exit 1
        end

        unless File.exist?(file_path)
          puts "\e[31mFile not found: #{file_path}\e[0m"
          exit 1
        end

        sub = find_subscription_by_product_id!(product_id)

        existing = client.subscription_review_screenshot(subscription_id: sub['id'])
        if existing
          puts "\e[33mThis subscription already has a review screenshot.\e[0m"
          print "\e[33mReplace existing screenshot? (y/N): \e[0m"
          confirm = $stdin.gets&.strip&.downcase
          return unless confirm == 'y'

          client.delete_subscription_review_screenshot(screenshot_id: existing[:id])
          puts "\e[32mDeleted existing review screenshot.\e[0m"
        end

        puts 'Uploading review screenshot...'
        result = client.upload_subscription_review_screenshot(subscription_id: sub['id'], file_path: file_path)
        puts "\e[32mReview screenshot uploaded!\e[0m"
        puts "  Screenshot ID: #{result['data']['id']}"
      rescue ApiError => e
        puts "\e[31mError: #{e.message}\e[0m"
      end

      def cmd_delete_sub_review_screenshot
        if @options.empty?
          puts "\e[31mUsage: asc delete-sub-review-screenshot <product_id>\e[0m"
          exit 1
        end

        product_id = @options.first
        sub = find_subscription_by_product_id!(product_id)
        screenshot = client.subscription_review_screenshot(subscription_id: sub['id'])

        unless screenshot
          puts "\e[33mNo review screenshot found for #{product_id}.\e[0m"
          return
        end

        print "\e[33mDelete review screenshot for #{product_id}? (y/N): \e[0m"
        confirm = $stdin.gets&.strip&.downcase
        return unless confirm == 'y'

        client.delete_subscription_review_screenshot(screenshot_id: screenshot[:id])
        puts "\e[32mReview screenshot deleted.\e[0m"
      rescue ApiError => e
        puts "\e[31mError: #{e.message}\e[0m"
      end

      def cmd_set_sub_tax_category
        if @options.length < 2
          puts "\e[31mUsage: asc set-sub-tax-category <product_id> <tax_category_id>\e[0m"
          exit 1
        end

        product_id = @options[0]
        tax_category_id = @options[1]
        sub = find_subscription_by_product_id!(product_id)

        print "\e[33mSet tax category for #{product_id} to #{tax_category_id}? (y/N): \e[0m"
        confirm = $stdin.gets&.strip&.downcase
        return unless confirm == 'y'

        client.update_subscription_tax_category(subscription_id: sub['id'], tax_category_id: tax_category_id)
        puts "\e[32mTax category updated.\e[0m"
      rescue ApiError => e
        puts "\e[31mError: #{e.message}\e[0m"
      end

      def cmd_tax_categories
        limit = 200
        if @options.any?
          begin
            limit = Integer(@options[0], 10)
          rescue ArgumentError, TypeError
            puts "\e[31mUsage: asc tax-categories [limit]\e[0m"
            exit 1
          end
        end

        categories = client.tax_categories(limit: limit)
        if categories.empty?
          puts 'No tax categories found.'
          return
        end

        puts "\e[1mTax Categories\e[0m"
        puts '=' * 50
        categories.each do |category|
          name = category[:name] || '(no name)'
          puts "  - #{category[:id]}: #{name}"
        end
      rescue ApiError => e
        puts "\e[31mError: #{e.message}\e[0m"
      end

      def cmd_sub_localizations
        if @options.empty?
          puts "\e[31mUsage: asc sub-localizations <product_id>\e[0m"
          exit 1
        end

        product_id = @options.first
        sub = find_subscription_by_product_id!(product_id)
        locs = client.subscription_localizations(subscription_id: sub['id'])

        if locs.empty?
          puts "\e[33mNo localizations found for #{product_id}.\e[0m"
          return
        end

        puts "\e[1mSubscription Localizations\e[0m"
        puts '=' * 50
        locs.each do |loc|
          puts "  #{loc[:locale]}: #{loc[:name]}"
          puts "    Description: #{loc[:description] || '(none)'}"
        end
      rescue ApiError => e
        puts "\e[31mError: #{e.message}\e[0m"
      end

      def cmd_update_sub_localization
        if @options.length < 2
          puts "\e[31mUsage: asc update-sub-localization <product_id> <locale> [--name \"Name\"] [--description \"Desc\"] [--create]\e[0m"
          exit 1
        end

        args = @options.dup
        product_id = args.shift
        locale = args.shift
        name = nil
        description = nil
        create = false

        while args.any?
          arg = args.shift
          case arg
          when '--name'
            name = args.shift
          when '--description'
            description = args.shift
          when '--create'
            create = true
          else
            puts "\e[31mUnknown argument: #{arg}\e[0m"
            exit 1
          end
        end

        if name.nil? && description.nil?
          puts "\e[31mProvide --name and/or --description.\e[0m"
          exit 1
        end

        sub = find_subscription_by_product_id!(product_id)
        locs = client.subscription_localizations(subscription_id: sub['id'])
        loc = locs.find { |l| l[:locale].casecmp?(locale) }

        if loc
          client.update_subscription_localization(
            localization_id: loc[:id],
            name: name,
            description: description
          )
          puts "\e[32mLocalization updated.\e[0m"
        elsif create
          if name.nil?
            puts "\e[31m--name is required when creating a localization.\e[0m"
            exit 1
          end
          client.create_subscription_localization(
            subscription_id: sub['id'],
            locale: locale,
            name: name,
            description: description
          )
          puts "\e[32mLocalization created.\e[0m"
        else
          puts "\e[31mLocalization not found for #{locale}. Use --create to add it.\e[0m"
          exit 1
        end
      rescue ApiError => e
        puts "\e[31mError: #{e.message}\e[0m"
      end

      def cmd_sub_intro_offers
        if @options.empty?
          puts "\e[31mUsage: asc sub-intro-offers <product_id>\e[0m"
          exit 1
        end

        product_id = @options.first
        sub = find_subscription_by_product_id!(product_id)
        offers = client.subscription_introductory_offers(subscription_id: sub['id'])

        if offers.empty?
          puts "\e[33mNo introductory offers found for #{product_id}.\e[0m"
          return
        end

        puts "\e[1mSubscription Introductory Offers\e[0m"
        puts '=' * 50
        offers.each do |offer|
          puts "  ID: #{offer[:id]}"
          puts "    Mode: #{offer[:offer_mode]}"
          puts "    Duration: #{offer[:duration]}"
          puts "    Periods: #{offer[:number_of_periods]}" if offer[:number_of_periods]
          puts "    Start: #{offer[:start_date]}" if offer[:start_date]
          puts "    End: #{offer[:end_date]}" if offer[:end_date]
          puts "    Price Point: #{offer[:price_point_id]}" if offer[:price_point_id]
        end
      rescue ApiError => e
        puts "\e[31mError: #{e.message}\e[0m"
      end

      def cmd_delete_sub_intro_offer
        if @options.empty?
          puts "\e[31mUsage: asc delete-sub-intro-offer <offer_id>\e[0m"
          exit 1
        end

        offer_id = @options.first
        print "\e[33mDelete introductory offer #{offer_id}? (y/N): \e[0m"
        confirm = $stdin.gets&.strip&.downcase
        return unless confirm == 'y'

        client.delete_subscription_introductory_offer(offer_id: offer_id)
        puts "\e[32mIntroductory offer deleted.\e[0m"
      rescue ApiError => e
        puts "\e[31mError: #{e.message}\e[0m"
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
          locs = []
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

          if attrs['state'] == 'MISSING_METADATA'
            puts "  \e[1mMetadata Status:\e[0m"
            subscription_metadata_status(sub_id, product_id: attrs['productId'], localizations: locs).each do |line|
              puts "    #{line}"
            end
            puts
          end
        end
      end

      def cmd_sub_ensure_assets
        if @options.empty?
          puts "\e[31mUsage: asc sub-ensure-assets [options]\e[0m"
          puts 'Ensures each subscription has required assets (review screenshot + 1024x1024 image).'
          puts
          puts 'Options:'
          puts '  --review-screenshot PATH     File to upload as the review screenshot (applied to all subs)'
          puts '  --capture                    Capture current simulator screen and use it as review screenshot'
          puts '  --output PATH                Output path for --capture (default: ./subscription-review.png)'
          puts '  --simulator-id ID            Simulator device UDID for --capture'
          puts '  --simulator-name NAME        Simulator device name for --capture (exact match)'
          puts '  --image-file PATH            1024x1024 image to upload (applied to all subs)'
          puts '  --image-dir DIR              Directory containing per-sub images (default pattern: %{product_id}.(png|jpg|jpeg))'
          puts '  --image-pattern PATTERN      Filename pattern inside --image-dir (supports %{product_id})'
          puts '  --only-missing               Skip subscriptions that already have the asset(s)'
          puts '  --replace                    Replace existing assets (deletes then uploads)'
          puts '  --wait                        Wait for assetDeliveryState COMPLETE after uploads'
          puts '  --timeout SECONDS            Max wait per asset (default: 300)'
          puts '  --interval SECONDS           Poll interval when waiting (default: 5)'
          puts '  --dry-run                    Print what would change without uploading'
          puts '  --yes                        Skip confirmation prompts'
          exit 1
        end

        args = @options.dup
        review_screenshot_path = nil
        capture = false
        output_path = nil
        simulator_id = nil
        simulator_name = nil
        image_file = nil
        image_dir = nil
        image_pattern = nil
        only_missing = false
        replace = false
        wait_complete = false
        timeout = 300
        interval = 5
        dry_run = false
        no_confirm = false
        unknown = []

        while args.any?
          arg = args.shift
          case arg
          when '--review-screenshot'
            review_screenshot_path = args.shift
          when '--capture'
            capture = true
          when '--output'
            output_path = args.shift
          when '--simulator-id'
            simulator_id = args.shift
          when '--simulator-name'
            simulator_name = args.shift
          when '--image-file'
            image_file = args.shift
          when '--image-dir'
            image_dir = args.shift
          when '--image-pattern'
            image_pattern = args.shift
          when '--only-missing'
            only_missing = true
          when '--replace'
            replace = true
          when '--wait'
            wait_complete = true
          when '--timeout'
            timeout = args.shift
          when '--interval'
            interval = args.shift
          when '--dry-run'
            dry_run = true
          when '--yes', '--no-confirm'
            no_confirm = true
          else
            unknown << arg
          end
        end

        if unknown.any?
          puts "\e[31mUnknown arguments: #{unknown.join(' ')}\e[0m"
          exit 1
        end

        if output_path && !capture
          puts "\e[31m--output requires --capture.\e[0m"
          exit 1
        end

        if (simulator_id || simulator_name) && !capture
          puts "\e[31m--simulator-id/--simulator-name require --capture.\e[0m"
          exit 1
        end

        if simulator_id && simulator_name
          puts "\e[31mPlease provide only one of --simulator-id or --simulator-name.\e[0m"
          exit 1
        end

        if capture && review_screenshot_path
          puts "\e[31mUse either --review-screenshot or --capture, not both.\e[0m"
          exit 1
        end

        begin
          timeout = Integer(timeout, 10)
          interval = Integer(interval, 10)
        rescue ArgumentError, TypeError
          puts "\e[31m--timeout and --interval must be integers (seconds).\e[0m"
          exit 1
        end

        if timeout < 1 || interval < 1
          puts "\e[31m--timeout and --interval must be >= 1.\e[0m"
          exit 1
        end

        if !dry_run && !capture && review_screenshot_path.nil? && image_file.nil? && image_dir.nil?
          puts "\e[31mProvide at least one of --review-screenshot/--capture or --image-file/--image-dir (or use --dry-run).\e[0m"
          exit 1
        end

        if json? && !no_confirm && !dry_run
          puts "\e[31m--json requires --yes or --no-confirm to avoid interactive prompts.\e[0m"
          exit 1
        end

        if capture
          review_screenshot_path = output_path || 'subscription-review.png'
          begin
            capture_simulator_screenshot(
              review_screenshot_path,
              simulator_id: simulator_id,
              simulator_name: simulator_name
            )
          rescue StandardError => e
            puts "\e[31mScreenshot capture failed: #{e.message}\e[0m"
            exit 1
          end
        end

        if review_screenshot_path && !File.exist?(review_screenshot_path)
          puts "\e[31mFile not found: #{review_screenshot_path}\e[0m"
          exit 1
        end

        if image_file && !File.exist?(image_file)
          puts "\e[31mFile not found: #{image_file}\e[0m"
          exit 1
        end

        if image_dir && !Dir.exist?(image_dir)
          puts "\e[31mDirectory not found: #{image_dir}\e[0m"
          exit 1
        end

        subs = client.subscriptions
        if subs.empty?
          puts "\e[33mNo subscriptions found.\e[0m"
          return
        end

        planned = subs.map do |s|
          pid = s.dig('attributes', 'productId')
          review = client.subscription_review_screenshot(subscription_id: s['id'])
          images = client.subscription_images(subscription_id: s['id'])
          image_path = resolve_subscription_image_path(
            product_id: pid,
            image_file: image_file,
            image_dir: image_dir,
            image_pattern: image_pattern
          )

          {
            id: s['id'],
            product_id: pid,
            review_present: !review.nil?,
            images_present: images.any?,
            review_screenshot_path: review_screenshot_path,
            image_path: image_path,
            skip: only_missing && review && images.any?
          }
        end

        planned.reject! { |p| p[:skip] }

        if planned.empty?
          puts "\e[32mNothing to do.\e[0m" unless quiet?
          output_json({ ok: true, planned: [] }) if json?
          return
        end

        missing_review_without_file = planned.any? { |p| (replace || !p[:review_present]) && p[:review_screenshot_path].nil? }
        missing_image_without_file = planned.any? { |p| (replace || !p[:images_present]) && p[:image_path].nil? }

        if !dry_run && (missing_review_without_file || missing_image_without_file)
          puts "\e[31mMissing input files:\e[0m"
          puts "  Review screenshot file is required (use --review-screenshot or --capture)." if missing_review_without_file
          puts "  Image file(s) required (use --image-file or --image-dir)." if missing_image_without_file
          exit 1
        end

        if dry_run
          result = planned.map do |p|
            {
              product_id: p[:product_id],
              would_upload_review_screenshot: (replace || !p[:review_present]),
              would_upload_image: (replace || !p[:images_present]),
              review_screenshot_path: p[:review_screenshot_path],
              image_path: p[:image_path]
            }
          end

          if json?
            output_json({ ok: true, dry_run: true, subscriptions: result })
          else
            puts "\e[1mSubscription Assets (Dry Run)\e[0m"
            puts '=' * 50
            result.each do |r|
              puts "#{r[:product_id]}:"
              puts "  Review Screenshot: #{r[:would_upload_review_screenshot] ? 'UPLOAD' : 'ok'}"
              puts "  Image: #{r[:would_upload_image] ? 'UPLOAD' : 'ok'}"
            end
          end
          return
        end

        unless no_confirm
          puts "\e[1mEnsure Subscription Assets\e[0m"
          puts '=' * 50
          planned.each { |p| puts p[:product_id] }
          puts
          puts "  Replace existing: #{replace ? 'yes' : 'no'}"
          puts "  Wait for COMPLETE: #{wait_complete ? 'yes' : 'no'}"
          puts
          print "\e[33mProceed? (y/N): \e[0m"
          confirm = $stdin.gets&.strip&.downcase
          return unless confirm == 'y'
        end

        results = []
        planned.each do |p|
          pid = p[:product_id]
          sub_id = p[:id]
          entry = { product_id: pid, subscription_id: sub_id, actions: [] }

          if replace || !p[:review_present]
            existing = client.subscription_review_screenshot(subscription_id: sub_id)
            if existing && replace
              client.delete_subscription_review_screenshot(screenshot_id: existing[:id])
              entry[:actions] << { action: 'delete_review_screenshot', id: existing[:id] }
            end

            if p[:review_screenshot_path]
              reservation = client.upload_subscription_review_screenshot(subscription_id: sub_id, file_path: p[:review_screenshot_path])
              screenshot_id = reservation.dig('data', 'id')
              entry[:actions] << { action: 'upload_review_screenshot', id: screenshot_id, file: p[:review_screenshot_path] }

              if wait_complete && screenshot_id
                wait_for_subscription_asset(type: :review_screenshot, id: screenshot_id, timeout: timeout, interval: interval)
                entry[:actions] << { action: 'wait_review_screenshot_complete', id: screenshot_id }
              end
            end
          end

          if replace || !p[:images_present]
            existing_images = client.subscription_images(subscription_id: sub_id)
            if existing_images.any? && replace
              existing_images.each do |img|
                client.delete_subscription_image(image_id: img[:id])
                entry[:actions] << { action: 'delete_image', id: img[:id] }
              end
            end

            if p[:image_path]
              reservation = client.upload_subscription_image(subscription_id: sub_id, file_path: p[:image_path])
              image_id = reservation.dig('data', 'id')
              entry[:actions] << { action: 'upload_image', id: image_id, file: p[:image_path] }

              if wait_complete && image_id
                wait_for_subscription_asset(type: :image, id: image_id, timeout: timeout, interval: interval)
                entry[:actions] << { action: 'wait_image_complete', id: image_id }
              end
            end
          end

          results << entry
        end

        if json?
          output_json({ ok: true, subscriptions: results })
        else
          puts "\e[32mDone.\e[0m"
        end
      rescue ApiError => e
        puts "\e[31mError: #{e.message}\e[0m"
      end

      def cmd_sub_metadata_status
        if @options.empty?
          puts "\e[31mUsage: asc sub-metadata-status <product_id> [--json]\e[0m"
          puts "\e[31mUsage: asc sub-metadata-status --all [--json]\e[0m"
          exit 1
        end

        args = @options.dup
        all = args.delete('--all')
        product_id = all ? nil : args.shift

        if !all && (product_id.nil? || product_id.strip.empty?)
          puts "\e[31mMissing product_id. Use --all to check all subscriptions.\e[0m"
          exit 1
        end

        subs = client.subscriptions
        targets =
          if all
            subs.select { |s| s.dig('attributes', 'state') == 'MISSING_METADATA' }
          else
            [find_subscription_by_product_id!(product_id)]
          end

        if json?
          payload = {
            subscriptions: targets.map do |s|
              attrs = s['attributes'] || {}
              checks = subscription_metadata_checks(s['id'])
              {
                id: s['id'],
                product_id: attrs['productId'],
                name: attrs['name'],
                state: attrs['state'],
                group_level: attrs['groupLevel'],
                checks: checks
              }
            end
          }
          output_json(payload)
          return
        end

        targets.each do |s|
          attrs = s['attributes'] || {}
          puts "\e[1m#{attrs['name']}\e[0m (ID: #{s['id']})"
          puts "  Product ID: #{attrs['productId']}"
          puts "  State: #{attrs['state']}"
          puts "  Group Level: #{attrs['groupLevel']}"
          puts
          subscription_metadata_status(s['id'], product_id: attrs['productId']).each do |line|
            puts "  - #{line}"
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
        puts '  --localizations-file <path> JSON or YAML list of localizations'
        puts '  --add-localization <loc:name:desc> Add a localization (repeatable)'
        puts '  --price-point <id>          Subscription price point id'
        puts '  --price-territory <ISO>     Validate price point for territory (e.g., USA)'
        puts '  --price-start-date <date>   Price start date (YYYY-MM-DD)'
        puts '  --intro-offer <type>        FREE_TRIAL, PAY_AS_YOU_GO, PAY_UP_FRONT'
        puts '  --intro-duration <period>   Intro duration (same as subscription periods)'
        puts '  --intro-price-point <id>    Price point for intro offer'
        puts '  --dry-run                   Validate without creating'
        puts '  --yes, --no-confirm         Skip confirmation prompt'
        puts '  --json                      JSON output (requires --yes)'
      end

      def print_fix_sub_metadata_usage
        puts "\e[31mUsage: asc fix-sub-metadata <product_id> [options]\e[0m"
        puts 'Example: asc fix-sub-metadata com.example.app.plan.monthly --display-name "Monthly Plan" --description "Access premium features" --price-point PRICE_POINT_ID'
        puts
        puts 'Options:'
        puts '  --locale <locale>           Localization locale (default: en-US)'
        puts '  --display-name "text"       Localized display name'
        puts '  --description "text"        Localized description'
        puts '  --localizations-file <path> JSON or YAML list of localizations'
        puts '  --add-localization <loc:name:desc> Add a localization (repeatable)'
        puts '  --price-point <id>          Subscription price point id'
        puts '  --price-territory <ISO>     Validate price point for territory (e.g., USA)'
        puts '  --price-start-date <date>   Price start date (YYYY-MM-DD)'
        puts '  --intro-offer <type>        FREE_TRIAL, PAY_AS_YOU_GO, PAY_UP_FRONT'
        puts '  --intro-duration <period>   Intro duration (same as subscription periods)'
        puts '  --intro-price-point <id>    Price point for intro offer'
        puts '  --dry-run                   Validate without creating'
        puts '  --yes, --no-confirm         Skip confirmation prompt'
        puts '  --json                      JSON output (requires --yes)'
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

      def find_subscription_by_product_id!(product_id)
        subs = client.subscriptions
        sub = subs.find { |s| s.dig('attributes', 'productId') == product_id }

        unless sub
          puts "\e[31mSubscription not found: #{product_id}\e[0m"
          puts
          puts 'Available subscriptions:'
          subs.each do |s|
            puts "  - #{s.dig('attributes', 'productId')}"
          end
          exit 1
        end

        sub
      end

      def parse_localization_arg(value)
        parts = value.to_s.split(':', 3)
        if parts.length < 2
          raise ArgumentError, "Invalid --add-localization value: #{value}"
        end
        locale = parts[0].to_s.strip
        name = parts[1].to_s.strip
        description = parts[2]&.strip
        if locale.empty? || name.empty?
          raise ArgumentError, "Invalid --add-localization value: #{value}"
        end
        { locale: locale, name: name, description: description }
      rescue ArgumentError => e
        puts "\e[31m#{e.message}\e[0m"
        exit 1
      end

      def load_localizations_file(path)
        unless path && File.exist?(path)
          puts "\e[31mLocalizations file not found: #{path}\e[0m"
          exit 1
        end

        data =
          if path.end_with?('.json')
            JSON.parse(File.read(path))
          else
            YAML.safe_load(File.read(path), aliases: true)
          end

        data = data['localizations'] if data.is_a?(Hash) && data['localizations']
        data = data[:localizations] if data.is_a?(Hash) && data[:localizations]

        unless data.is_a?(Array)
          puts "\e[31mLocalizations file must contain a list of localizations.\e[0m"
          exit 1
        end

        data.map do |entry|
          unless entry.is_a?(Hash)
            puts "\e[31mInvalid localization entry in file: #{entry.inspect}\e[0m"
            exit 1
          end
          locale = entry['locale'] || entry[:locale]
          name = entry['name'] || entry[:name]
          description = entry['description'] || entry[:description]
          if locale.to_s.strip.empty? || name.to_s.strip.empty?
            puts "\e[31mLocalization entries require locale and name.\e[0m"
            exit 1
          end
          { locale: locale, name: name, description: description }
        end
      rescue JSON::ParserError, Psych::SyntaxError => e
        puts "\e[31mFailed to parse localizations file: #{e.message}\e[0m"
        exit 1
      end

      def normalize_localizations!(localizations)
        seen = {}
        localizations.each do |loc|
          key = loc[:locale].to_s.downcase
          if seen[key]
            puts "\e[31mDuplicate localization for locale #{loc[:locale]}.\e[0m"
            exit 1
          end
          seen[key] = true
        end
      end

      def output_dry_run(json_output:, product_id:, name:, period:, group_id:, group_display:, create_group:,
                         localizations:, price_point_id:, price_territory:, price_start_date:,
                         intro_offer_mode:, intro_duration:, intro_price_point_id:)
        if json_output
          puts JSON.pretty_generate(
            dry_run: true,
            subscription: {
              product_id: product_id,
              name: name,
              period: period,
              group_id: group_id,
              group_name: group_display,
              create_group: create_group
            },
            localizations: localizations,
            price: {
              price_point_id: price_point_id,
              territory: price_territory,
              start_date: price_start_date
            },
            introductory_offer: {
              offer_mode: intro_offer_mode,
              duration: intro_duration,
              price_point_id: intro_price_point_id
            }
          )
        else
          puts "\e[33mDry run: no changes made.\e[0m"
        end
      end

      def output_metadata_dry_run(json_output:, product_id:, subscription_id:, localizations:, skipped_localizations:,
                                  price_point_id:, price_territory:, price_start_date:,
                                  intro_offer_mode:, intro_duration:, intro_price_point_id:)
        if json_output
          puts JSON.pretty_generate(
            dry_run: true,
            subscription: {
              id: subscription_id,
              product_id: product_id
            },
            localizations: localizations,
            skipped_localizations: skipped_localizations,
            price: {
              price_point_id: price_point_id,
              territory: price_territory,
              start_date: price_start_date
            },
            introductory_offer: {
              offer_mode: intro_offer_mode,
              duration: intro_duration,
              price_point_id: intro_price_point_id
            }
          )
        else
          puts "\e[33mDry run: no changes made.\e[0m"
        end
      end

      def parse_bool(value)
        case value.to_s.strip.downcase
        when 'true', 'yes', '1'
          true
        when 'false', 'no', '0'
          false
        else
          nil
        end
      end

      def normalize_price_value(value)
        return nil if value.nil?

        raw = value.to_s.strip
        raw = raw.gsub(',', '')
        raw = raw.gsub(/[^\d.]/, '')
        return nil if raw.empty?

        BigDecimal(raw).round(2).to_s('F')
      rescue ArgumentError
        nil
      end

      def capture_simulator_screenshot(file_path, simulator_id: nil, simulator_name: nil)
        unless RUBY_PLATFORM.include?('darwin')
          raise 'Simulator capture is only supported on macOS.'
        end

        dir = File.dirname(file_path)
        FileUtils.mkdir_p(dir) unless dir == '.'

        target = simulator_id || simulator_name || 'booted'
        cmd = ['xcrun', 'simctl', 'io', target, 'screenshot', file_path]
        output, status = Open3.capture2e(*cmd)

        unless status.success?
          raise output.strip.empty? ? 'simctl failed to capture screenshot.' : output.strip
        end

        unless File.exist?(file_path)
          raise "Screenshot capture failed; file not found at #{file_path}."
        end

        file_path
      rescue Errno::ENOENT
        raise 'xcrun not found. Install Xcode command line tools.'
      end

      def subscription_metadata_checks(subscription_id, localizations: nil)
        checks = {}

        locs = localizations
        if locs.nil?
          begin
            locs = client.subscription_localizations(subscription_id: subscription_id)
          rescue ApiError => e
            checks[:localizations] = { status: 'unknown', error: e.message }
            locs = []
          end
        end

        checks[:localizations] ||= if locs.any?
                                    { status: 'ok', count: locs.size }
                                  else
                                    { status: 'missing' }
                                  end

        begin
          availability = client.subscription_availability(subscription_id: subscription_id)
          if availability.nil? || availability[:territories].empty?
            checks[:availability] = { status: 'missing' }
          else
            checks[:availability] = {
              status: 'ok',
              territories_count: availability[:territories].size,
              available_in_new_territories: availability[:available_in_new_territories]
            }
          end
        rescue ApiError => e
          checks[:availability] = { status: 'unknown', error: e.message }
        end

        begin
          prices = client.subscription_prices(subscription_id: subscription_id)
          checks[:prices] = if prices.empty?
                              { status: 'missing' }
                            else
                              { status: 'ok', count: prices.size }
                            end
        rescue ApiError => e
          checks[:prices] = { status: 'unknown', error: e.message }
        end

        begin
          screenshot = client.subscription_review_screenshot(subscription_id: subscription_id)
          checks[:review_screenshot] = if screenshot.nil?
                                         { status: 'missing' }
                                       else
                                         { status: 'ok', file_name: screenshot[:file_name], upload_state: screenshot[:upload_state] }
                                       end
        rescue ApiError => e
          checks[:review_screenshot] = { status: 'unknown', error: e.message }
        end

        begin
          images = client.subscription_images(subscription_id: subscription_id)
          checks[:image] = if images.empty?
                             { status: 'none' }
                           else
                             { status: 'ok', count: images.size }
                           end
        rescue ApiError => e
          checks[:image] = { status: 'unknown', error: e.message }
        end

        begin
          tax_category = client.subscription_tax_category(subscription_id: subscription_id)
          checks[:tax_category] = if tax_category.nil?
                                    { status: 'unset' }
                                  else
                                    { status: 'ok', id: tax_category[:id], name: tax_category[:name] }
                                  end
        rescue ApiError => e
          checks[:tax_category] = { status: 'unknown', error: e.message }
        end

        checks
      end

      def subscription_metadata_status(subscription_id, product_id: nil, localizations: nil)
        checks = subscription_metadata_checks(subscription_id, localizations: localizations)
        pid = product_id || '<product_id>'

        lines = []

        loc = checks[:localizations]
        case loc[:status]
        when 'ok'
          lines << "Localizations: OK (#{loc[:count]})"
        when 'missing'
          lines << "Localizations: MISSING (use: asc update-sub-localization #{pid} en-US ...)"
        else
          lines << "Localizations: Unknown (#{loc[:error]})"
        end

        avail = checks[:availability]
        case avail[:status]
        when 'ok'
          detail = "#{avail[:territories_count]} territories"
          new_territories = avail[:available_in_new_territories]
          detail += ", new territories: #{new_territories.nil? ? 'unset' : new_territories}"
          lines << "Availability: OK (#{detail})"
          if new_territories.nil?
            lines << "Availability: availableInNewTerritories missing (use: asc set-sub-availability #{pid} --available-in-new-territories true|false ...)"
          end
        when 'missing'
          lines << "Availability: MISSING (use: asc set-sub-availability #{pid} ...)"
        else
          lines << "Availability: Unknown (#{avail[:error]})"
        end

        prices = checks[:prices]
        case prices[:status]
        when 'ok'
          lines << "Price Schedule: OK (#{prices[:count]} price(s))"
        when 'missing'
          lines << "Price Schedule: MISSING (use: asc add-sub-price #{pid} <price_point_id> ...)"
        else
          lines << "Price Schedule: Unknown (#{prices[:error]})"
        end

        rs = checks[:review_screenshot]
        case rs[:status]
        when 'ok'
          state = rs[:upload_state] ? " (#{rs[:upload_state]})" : ''
          lines << "Review Screenshot: OK (#{rs[:file_name]}#{state})"
        when 'missing'
          lines << "Review Screenshot: MISSING (use: asc upload-sub-review-screenshot #{pid} <file>)"
        else
          lines << "Review Screenshot: Unknown (#{rs[:error]})"
        end

        img = checks[:image]
        case img[:status]
        when 'ok'
          lines << "Image: OK (#{img[:count]} image(s))"
        when 'none'
          lines << 'Image: None (optional unless using offers/promotions)'
        else
          lines << "Image: Unknown (#{img[:error]})"
        end

        tax = checks[:tax_category]
        case tax[:status]
        when 'ok'
          label = tax[:name] || tax[:id]
          lines << "Tax Category: OK (#{label})"
        when 'unset'
          lines << 'Tax Category: Not set (set in App Store Connect UI if required)'
        else
          lines << "Tax Category: Unavailable (#{tax[:error]})"
        end

        lines
      end

      def resolve_subscription_image_path(product_id:, image_file:, image_dir:, image_pattern:)
        return image_file if image_file
        return nil unless image_dir

        pattern = (image_pattern || '%{product_id}')
        base = format(pattern, product_id: product_id)

        candidates = [
          File.join(image_dir, base),
          File.join(image_dir, "#{base}.png"),
          File.join(image_dir, "#{base}.jpg"),
          File.join(image_dir, "#{base}.jpeg"),
          File.join(image_dir, "#{product_id}.png"),
          File.join(image_dir, "#{product_id}.jpg"),
          File.join(image_dir, "#{product_id}.jpeg")
        ].uniq

        candidates.find { |path| File.exist?(path) }
      end

      def wait_for_subscription_asset(type:, id:, timeout:, interval:)
        deadline = Time.now + timeout
        loop do
          state = case type
                  when :review_screenshot
                    client.subscription_review_screenshot_by_id(screenshot_id: id)&.dig(:upload_state)
                  when :image
                    client.subscription_image(image_id: id)&.dig(:upload_state)
                  else
                    raise ArgumentError, "Unknown asset type: #{type}"
                  end

          return if state == 'COMPLETE'

          if Time.now >= deadline
            raise ApiError, "Timed out waiting for #{type} #{id} to reach COMPLETE (last state: #{state || 'unknown'})."
          end

          sleep(interval)
        end
      end
    end
  end
end
