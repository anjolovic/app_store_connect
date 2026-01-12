# frozen_string_literal: true

module AppStoreConnect
  class CLI
    # User management CLI commands
    module Users
      def cmd_users
        puts "\e[1mTeam Users\e[0m"
        puts '=' * 50
        puts

        users = client.users
        if users.empty?
          puts 'No users found.'
          return
        end

        users.each do |user|
          puts "\e[1m#{user[:first_name]} #{user[:last_name]}\e[0m"
          puts "  ID: #{user[:id]}"
          puts "  Email: #{user[:email]}"
          puts "  Username: #{user[:username]}"
          puts "  Roles: #{user[:roles]&.join(', ') || 'None'}"
          puts "  All Apps Visible: #{user[:all_apps_visible] ? 'Yes' : 'No'}"
          puts
        end
      end

      def cmd_invitations
        puts "\e[1mPending Invitations\e[0m"
        puts '=' * 50
        puts

        invitations = client.user_invitations
        if invitations.empty?
          puts 'No pending invitations.'
          return
        end

        invitations.each do |invite|
          expires = invite[:expiration_date] ? Time.parse(invite[:expiration_date]).strftime('%Y-%m-%d') : 'N/A'

          puts "\e[1m#{invite[:first_name]} #{invite[:last_name]}\e[0m"
          puts "  ID: #{invite[:id]}"
          puts "  Email: #{invite[:email]}"
          puts "  Roles: #{invite[:roles]&.join(', ') || 'None'}"
          puts "  Expires: #{expires}"
          puts
        end
      end

      def cmd_invite_user
        if @options.length < 4
          puts "\e[31mUsage: asc invite-user <email> <first_name> <last_name> <role> [role...]\e[0m"
          puts 'Example: asc invite-user jane@example.com Jane Doe DEVELOPER'
          puts 'Example: asc invite-user john@example.com John Smith APP_MANAGER MARKETING'
          puts
          puts 'Available roles:'
          puts '  ADMIN, FINANCE, ACCOUNT_HOLDER, SALES, MARKETING, APP_MANAGER,'
          puts '  DEVELOPER, ACCESS_TO_REPORTS, CUSTOMER_SUPPORT, CREATE_APPS'
          exit 1
        end

        email = @options[0]
        first_name = @options[1]
        last_name = @options[2]
        roles = @options[3..]

        result = client.create_user_invitation(
          email: email,
          first_name: first_name,
          last_name: last_name,
          roles: roles
        )

        puts "\e[32mInvitation sent!\e[0m"
        puts "  Email: #{result[:email]}"
        puts "  Roles: #{result[:roles]&.join(', ')}"
        puts "  Expires: #{result[:expiration_date]}"
      end

      def cmd_remove_user
        if @options.empty?
          puts "\e[31mUsage: asc remove-user <user_id>\e[0m"
          puts "Use 'asc users' to find user IDs."
          exit 1
        end

        user_id = @options[0]

        # Get user details for confirmation
        begin
          user = client.user(user_id: user_id)
          puts "User: #{user[:first_name]} #{user[:last_name]} (#{user[:email]})"
        rescue ApiError
          puts "\e[31mUser not found: #{user_id}\e[0m"
          exit 1
        end

        print "\e[33mRemove this user from the team? (y/N): \e[0m"
        confirm = $stdin.gets.chomp.downcase

        if confirm == 'y'
          client.delete_user(user_id: user_id)
          puts "\e[32mUser removed from team.\e[0m"
        else
          puts 'Cancelled.'
        end
      end

      def cmd_cancel_invitation
        if @options.empty?
          puts "\e[31mUsage: asc cancel-invitation <invitation_id>\e[0m"
          puts "Use 'asc invitations' to find invitation IDs."
          exit 1
        end

        invitation_id = @options[0]

        print "Cancel invitation #{invitation_id}? (y/N): "
        confirm = $stdin.gets.chomp.downcase

        if confirm == 'y'
          client.delete_user_invitation(invitation_id: invitation_id)
          puts "\e[32mInvitation cancelled.\e[0m"
        else
          puts 'Cancelled.'
        end
      end
    end
  end
end
