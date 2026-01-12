# frozen_string_literal: true

module AppStoreConnect
  class CLI
    # Privacy-related CLI commands (reference only - API not supported for CRUD)
    module Privacy
      def cmd_privacy_labels
        puts "\e[1mApp Privacy Labels\e[0m"
        puts '=' * 50
        puts
        puts "\e[33mNote: Apple's API does not support reading privacy declarations.\e[0m"
        puts
        puts 'To view or edit your App Privacy labels:'
        puts '  1. Go to https://appstoreconnect.apple.com'
        puts '  2. Select your app'
        puts '  3. Click "App Privacy" in the sidebar'
        puts
        puts 'Use these commands for reference when filling out the questionnaire:'
        puts '  asc privacy-types     - List all data types'
        puts '  asc privacy-purposes  - List all purposes'
      end

      def cmd_privacy_types
        puts "\e[1mPrivacy Data Types Reference\e[0m"
        puts '=' * 50
        puts
        puts 'Use this reference when completing the App Privacy questionnaire.'
        puts

        # Group by category
        types_by_category = client.privacy_data_types.group_by { |t| t[:category] }

        types_by_category.each do |category, types|
          puts "\e[1m#{category}:\e[0m"
          types.each do |type|
            puts "  - #{type[:name]} (#{type[:id]})"
          end
          puts
        end

        puts "\e[1mData Protection Levels:\e[0m"
        client.privacy_protection_levels.each do |level|
          puts "  - #{level[:name]}"
          puts "    #{level[:description]}"
        end
      end

      def cmd_privacy_purposes
        puts "\e[1mPrivacy Purposes Reference\e[0m"
        puts '=' * 50
        puts
        puts 'Use this reference when completing the App Privacy questionnaire.'
        puts

        client.privacy_purposes.each do |purpose|
          puts "\e[1m#{purpose[:name]}\e[0m"
          puts "  ID: #{purpose[:id]}"
          puts "  #{purpose[:description]}"
          puts
        end
      end
    end
  end
end
