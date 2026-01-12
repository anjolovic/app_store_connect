# frozen_string_literal: true

module AppStoreConnect
  class CLI
    # TestFlight CLI commands
    module TestFlight
      def cmd_testers
        puts "\e[1mBeta Testers\e[0m"
        puts '=' * 50
        puts

        testers = client.beta_testers
        if testers.empty?
          puts 'No beta testers found.'
          return
        end

        testers.each do |tester|
          state_color = case tester[:state]
                        when 'INSTALLED' then "\e[32m"
                        when 'INVITED' then "\e[33m"
                        else "\e[0m"
                        end

          puts "\e[1m#{tester[:first_name]} #{tester[:last_name]}\e[0m"
          puts "  ID: #{tester[:id]}"
          puts "  Email: #{tester[:email]}"
          puts "  State: #{state_color}#{tester[:state]}\e[0m"
          puts "  Invite Type: #{tester[:invite_type]}"
          puts
        end
      end

      def cmd_tester_groups
        puts "\e[1mBeta Groups\e[0m"
        puts '=' * 50
        puts

        groups = client.beta_groups
        if groups.empty?
          puts 'No beta groups found.'
          return
        end

        groups.each do |group|
          internal_label = group[:is_internal] ? "\e[33m[Internal]\e[0m" : ''

          puts "\e[1m#{group[:name]}\e[0m #{internal_label}"
          puts "  ID: #{group[:id]}"
          puts "  Public Link: #{group[:public_link_enabled] ? 'Enabled' : 'Disabled'}"
          puts "  Public URL: #{group[:public_link]}" if group[:public_link]
          puts "  Created: #{group[:created_date]}"
          puts
        end
      end

      def cmd_add_tester
        if @options.empty?
          puts "\e[31mUsage: asc add-tester <email> [first_name] [last_name] [group_id...]\e[0m"
          puts 'Example: asc add-tester test@example.com John Doe'
          puts 'Example: asc add-tester test@example.com John Doe group_id_1 group_id_2'
          exit 1
        end

        email = @options[0]
        first_name = @options[1]
        last_name = @options[2]
        group_ids = @options[3..] || []

        result = client.create_beta_tester(
          email: email,
          first_name: first_name,
          last_name: last_name,
          group_ids: group_ids
        )

        puts "\e[32mBeta tester added!\e[0m"
        puts "  Email: #{result[:email]}"
        puts "  ID: #{result[:id]}"
        puts "  State: #{result[:state]}"
      end

      def cmd_remove_tester
        if @options.empty?
          puts "\e[31mUsage: asc remove-tester <tester_id>\e[0m"
          puts "Use 'asc testers' to find tester IDs."
          exit 1
        end

        tester_id = @options[0]

        print "Remove beta tester #{tester_id}? (y/N): "
        confirm = $stdin.gets.chomp.downcase

        if confirm == 'y'
          client.delete_beta_tester(tester_id: tester_id)
          puts "\e[32mBeta tester removed.\e[0m"
        else
          puts 'Cancelled.'
        end
      end

      def cmd_create_group
        if @options.empty?
          puts "\e[31mUsage: asc create-group <name> [--public] [--limit N]\e[0m"
          puts 'Example: asc create-group "External Testers"'
          puts 'Example: asc create-group "Public Beta" --public --limit 1000'
          exit 1
        end

        name = @options[0]
        public_link = @options.include?('--public')
        limit_idx = @options.index('--limit')
        limit = limit_idx ? @options[limit_idx + 1]&.to_i : nil

        result = client.create_beta_group(
          name: name,
          public_link_enabled: public_link,
          public_link_limit: limit,
          public_link_limit_enabled: !limit.nil?
        )

        puts "\e[32mBeta group created!\e[0m"
        puts "  Name: #{result[:name]}"
        puts "  ID: #{result[:id]}"
        puts "  Public Link: #{result[:public_link]}" if result[:public_link]
      end

      def cmd_delete_group
        if @options.empty?
          puts "\e[31mUsage: asc delete-group <group_id>\e[0m"
          puts "Use 'asc tester-groups' to find group IDs."
          exit 1
        end

        group_id = @options[0]

        # Get group details for confirmation
        begin
          group = client.beta_group(group_id: group_id)
          puts "Group: #{group[:name]}"
        rescue ApiError
          puts "\e[31mGroup not found: #{group_id}\e[0m"
          exit 1
        end

        print "\e[33mDelete this beta group? (y/N): \e[0m"
        confirm = $stdin.gets.chomp.downcase

        if confirm == 'y'
          client.delete_beta_group(group_id: group_id)
          puts "\e[32mBeta group deleted.\e[0m"
        else
          puts 'Cancelled.'
        end
      end

      def cmd_group_testers
        if @options.empty?
          puts "\e[31mUsage: asc group-testers <group_id>\e[0m"
          puts "Use 'asc tester-groups' to find group IDs."
          exit 1
        end

        group_id = @options[0]

        # Get group name
        begin
          group = client.beta_group(group_id: group_id)
          puts "\e[1mTesters in '#{group[:name]}'\e[0m"
          puts '=' * 50
          puts
        rescue ApiError
          puts "\e[31mGroup not found: #{group_id}\e[0m"
          exit 1
        end

        testers = client.beta_group_testers(group_id: group_id)

        if testers.empty?
          puts 'No testers in this group.'
          return
        end

        testers.each do |tester|
          state_color = case tester[:state]
                        when 'INSTALLED' then "\e[32m"
                        when 'INVITED' then "\e[33m"
                        else "\e[0m"
                        end

          puts "#{tester[:first_name]} #{tester[:last_name]} <#{tester[:email]}>"
          puts "  ID: #{tester[:id]}"
          puts "  State: #{state_color}#{tester[:state]}\e[0m"
          puts
        end
      end

      def cmd_add_to_group
        if @options.length < 2
          puts "\e[31mUsage: asc add-to-group <group_id> <tester_id> [tester_id...]\e[0m"
          puts 'Example: asc add-to-group abc123 tester1 tester2 tester3'
          exit 1
        end

        group_id = @options[0]
        tester_ids = @options[1..]

        client.add_testers_to_group(group_id: group_id, tester_ids: tester_ids)
        puts "\e[32mAdded #{tester_ids.length} tester(s) to group.\e[0m"
      end

      def cmd_remove_from_group
        if @options.length < 2
          puts "\e[31mUsage: asc remove-from-group <group_id> <tester_id> [tester_id...]\e[0m"
          puts 'Example: asc remove-from-group abc123 tester1 tester2'
          exit 1
        end

        group_id = @options[0]
        tester_ids = @options[1..]

        print "Remove #{tester_ids.length} tester(s) from group? (y/N): "
        confirm = $stdin.gets.chomp.downcase

        if confirm == 'y'
          client.remove_testers_from_group(group_id: group_id, tester_ids: tester_ids)
          puts "\e[32mRemoved #{tester_ids.length} tester(s) from group.\e[0m"
        else
          puts 'Cancelled.'
        end
      end

      def cmd_testflight_builds
        puts "\e[1mTestFlight Builds\e[0m"
        puts '=' * 50
        puts

        builds = client.testflight_builds
        if builds.empty?
          puts 'No TestFlight builds found.'
          return
        end

        builds.each do |build|
          state_color = case build[:processing_state]
                        when 'VALID' then "\e[32m"
                        when 'PROCESSING' then "\e[33m"
                        when 'FAILED', 'INVALID' then "\e[31m"
                        else "\e[0m"
                        end

          beta_color = case build[:external_state]
                       when 'READY_FOR_BETA_TESTING' then "\e[32m"
                       when 'IN_BETA_REVIEW', 'WAITING_FOR_BETA_REVIEW' then "\e[33m"
                       when 'REJECTED' then "\e[31m"
                       else "\e[0m"
                       end

          uploaded = build[:uploaded_date] ? Time.parse(build[:uploaded_date]).strftime('%Y-%m-%d %H:%M') : 'N/A'

          puts "Build #{build[:version]}"
          puts "  ID: #{build[:id]}"
          puts "  Processing: #{state_color}#{build[:processing_state]}\e[0m"
          puts "  External Beta: #{beta_color}#{build[:external_state]}\e[0m"
          puts "  Internal: #{build[:uses_non_exempt_encryption] == false ? 'Ready' : 'Check encryption'}"
          puts "  Uploaded: #{uploaded}"
          puts
        end
      end

      def cmd_distribute_build
        if @options.length < 2
          puts "\e[31mUsage: asc distribute-build <build_id> <group_id> [group_id...]\e[0m"
          puts "Use 'asc testflight-builds' to find build IDs."
          puts "Use 'asc tester-groups' to find group IDs."
          exit 1
        end

        build_id = @options[0]
        group_ids = @options[1..]

        client.add_build_to_groups(build_id: build_id, group_ids: group_ids)
        puts "\e[32mBuild distributed to #{group_ids.length} group(s).\e[0m"
      end

      def cmd_remove_build
        if @options.length < 2
          puts "\e[31mUsage: asc remove-build <build_id> <group_id> [group_id...]\e[0m"
          puts 'Remove a build from beta groups.'
          exit 1
        end

        build_id = @options[0]
        group_ids = @options[1..]

        print "Remove build from #{group_ids.length} group(s)? (y/N): "
        confirm = $stdin.gets.chomp.downcase

        if confirm == 'y'
          client.remove_build_from_groups(build_id: build_id, group_ids: group_ids)
          puts "\e[32mBuild removed from #{group_ids.length} group(s).\e[0m"
        else
          puts 'Cancelled.'
        end
      end

      def cmd_beta_whats_new
        if @options.empty?
          puts "\e[31mUsage: asc beta-whats-new <build_id>\e[0m"
          puts 'Show What\'s New text for a TestFlight build.'
          exit 1
        end

        build_id = @options[0]

        puts "\e[1mBeta Build What's New\e[0m"
        puts '=' * 50
        puts

        localizations = client.beta_build_localizations(build_id: build_id)

        if localizations.empty?
          puts 'No What\'s New text set for this build.'
          puts
          puts "Use 'asc update-beta-whats-new' to add release notes."
          return
        end

        localizations.each do |loc|
          puts "\e[1m#{loc[:locale]}:\e[0m"
          puts "  ID: #{loc[:id]}"
          puts "  #{loc[:whats_new] || '(no text)'}"
          puts
        end
      end

      def cmd_update_beta_whats_new
        if @options.length < 2
          puts "\e[31mUsage: asc update-beta-whats-new <build_id> \"What's new text\"\e[0m"
          puts 'Example: asc update-beta-whats-new abc123 "Bug fixes and improvements"'
          exit 1
        end

        build_id = @options[0]
        whats_new = @options[1..].join(' ')

        # Check for existing localization
        localizations = client.beta_build_localizations(build_id: build_id)
        en_loc = localizations.find { |l| l[:locale] == 'en-US' }

        if en_loc
          client.update_beta_build_localization(localization_id: en_loc[:id], whats_new: whats_new)
          puts "\e[32mUpdated What's New text!\e[0m"
        else
          client.create_beta_build_localization(build_id: build_id, locale: 'en-US', whats_new: whats_new)
          puts "\e[32mCreated What's New text!\e[0m"
        end

        puts "  Build: #{build_id}"
        puts "  What's New: #{whats_new}"
      end

      def cmd_submit_beta_review
        if @options.empty?
          puts "\e[31mUsage: asc submit-beta-review <build_id>\e[0m"
          puts 'Submit a build for external TestFlight beta review.'
          exit 1
        end

        build_id = @options[0]

        # Check current status
        existing = client.beta_app_review_submission(build_id: build_id)
        if existing
          puts "\e[33mThis build already has a beta review submission.\e[0m"
          puts "  State: #{existing[:beta_review_state]}"
          return
        end

        print 'Submit build for external beta review? (y/N): '
        confirm = $stdin.gets.chomp.downcase

        if confirm == 'y'
          result = client.submit_for_beta_review(build_id: build_id)
          puts "\e[32mBuild submitted for beta review!\e[0m"
          puts "  Build: #{build_id}"
          puts "  State: #{result[:beta_review_state]}"
        else
          puts 'Cancelled.'
        end
      end

      def cmd_beta_review_status
        if @options.empty?
          puts "\e[31mUsage: asc beta-review-status <build_id>\e[0m"
          puts 'Check the beta review status of a build.'
          exit 1
        end

        build_id = @options[0]

        puts "\e[1mBeta Review Status\e[0m"
        puts '=' * 50
        puts

        submission = client.beta_app_review_submission(build_id: build_id)

        if submission
          state_color = case submission[:beta_review_state]
                        when 'APPROVED' then "\e[32m"
                        when 'IN_REVIEW', 'WAITING_FOR_REVIEW' then "\e[33m"
                        when 'REJECTED' then "\e[31m"
                        else "\e[0m"
                        end

          puts "Build: #{build_id}"
          puts "State: #{state_color}#{submission[:beta_review_state]}\e[0m"
          puts "Submitted: #{submission[:submitted_date] || 'N/A'}"
        else
          puts 'No beta review submission found for this build.'
          puts
          puts "Use 'asc submit-beta-review #{build_id}' to submit for review."
        end
      end
    end
  end
end
