# frozen_string_literal: true

module AppStoreConnect
  class CLI
    # In-App Purchase CLI commands
    module InAppPurchases
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
    end
  end
end
