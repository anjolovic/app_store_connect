# frozen_string_literal: true

module AppStoreConnect
  class Client
    # User and invitation management methods
    module Users
      # List all users in the team
      def users(limit: 100)
        get("/users?limit=#{limit}")['data'].map do |user|
          {
            id: user['id'],
            username: user.dig('attributes', 'username'),
            first_name: user.dig('attributes', 'firstName'),
            last_name: user.dig('attributes', 'lastName'),
            email: user.dig('attributes', 'email'),
            roles: user.dig('attributes', 'roles'),
            all_apps_visible: user.dig('attributes', 'allAppsVisible'),
            provisioning_allowed: user.dig('attributes', 'provisioningAllowed')
          }
        end
      end

      # Get a single user
      def user(user_id:)
        result = get("/users/#{user_id}")['data']
        {
          id: result['id'],
          username: result.dig('attributes', 'username'),
          first_name: result.dig('attributes', 'firstName'),
          last_name: result.dig('attributes', 'lastName'),
          email: result.dig('attributes', 'email'),
          roles: result.dig('attributes', 'roles'),
          all_apps_visible: result.dig('attributes', 'allAppsVisible'),
          provisioning_allowed: result.dig('attributes', 'provisioningAllowed')
        }
      end

      # Update user roles
      def update_user(user_id:, roles: nil, all_apps_visible: nil)
        attributes = {}
        attributes[:roles] = roles if roles
        attributes[:allAppsVisible] = all_apps_visible unless all_apps_visible.nil?

        return nil if attributes.empty?

        patch("/users/#{user_id}", body: {
                data: {
                  type: 'users',
                  id: user_id,
                  attributes: attributes
                }
              })
      end

      # Remove a user from the team
      def delete_user(user_id:)
        delete("/users/#{user_id}")
      end

      # List pending user invitations
      def user_invitations(limit: 100)
        get("/userInvitations?limit=#{limit}")['data'].map do |invite|
          {
            id: invite['id'],
            email: invite.dig('attributes', 'email'),
            first_name: invite.dig('attributes', 'firstName'),
            last_name: invite.dig('attributes', 'lastName'),
            roles: invite.dig('attributes', 'roles'),
            expiration_date: invite.dig('attributes', 'expirationDate'),
            all_apps_visible: invite.dig('attributes', 'allAppsVisible'),
            provisioning_allowed: invite.dig('attributes', 'provisioningAllowed')
          }
        end
      end

      # Invite a new user
      def create_user_invitation(email:, first_name:, last_name:, roles:,
                                 all_apps_visible: true, provisioning_allowed: false,
                                 visible_app_ids: [])
        relationships = {}

        if visible_app_ids.any?
          relationships[:visibleApps] = {
            data: visible_app_ids.map { |id| { type: 'apps', id: id } }
          }
        end

        body = {
          data: {
            type: 'userInvitations',
            attributes: {
              email: email,
              firstName: first_name,
              lastName: last_name,
              roles: roles,
              allAppsVisible: all_apps_visible,
              provisioningAllowed: provisioning_allowed
            }
          }
        }

        body[:data][:relationships] = relationships if relationships.any?

        result = post('/userInvitations', body: body)

        {
          id: result['data']['id'],
          email: result['data'].dig('attributes', 'email'),
          roles: result['data'].dig('attributes', 'roles'),
          expiration_date: result['data'].dig('attributes', 'expirationDate')
        }
      end

      # Cancel a pending user invitation
      def delete_user_invitation(invitation_id:)
        delete("/userInvitations/#{invitation_id}")
      end
    end
  end
end
