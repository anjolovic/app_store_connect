# frozen_string_literal: true

module AppStoreConnect
  class CLI
    # Screenshot CLI commands (app and IAP)
    module Screenshots
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
          image_files = Dir.glob(File.join(type_dir, '*.{png,jpg,jpeg,PNG,JPG,JPEG}'))
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
        return unless errors.any?

        puts "\e[31mErrors:\e[0m"
        errors.each { |e| puts "  - #{e}" }
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
    end
  end
end
