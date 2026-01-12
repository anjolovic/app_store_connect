# frozen_string_literal: true

module AppStoreConnect
  class CLI
    # App administration CLI commands
    module Admin
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
    end
  end
end
