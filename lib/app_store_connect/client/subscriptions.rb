# frozen_string_literal: true

module AppStoreConnect
  class Client
    # Subscription management methods
    module Subscriptions
      # Get subscription groups
      def subscription_groups(target_app_id: nil)
        target_app_id ||= @app_id
        get("/apps/#{target_app_id}/subscriptionGroups")['data']
      end

      # Get all subscriptions
      def subscriptions(target_app_id: nil)
        target_app_id ||= @app_id
        groups = subscription_groups(target_app_id: target_app_id)
        groups.flat_map do |group|
          group_id = group['id']
          get("/subscriptionGroups/#{group_id}/subscriptions")['data']
        end
      end

      # Update subscription metadata (name, group level)
      def update_subscription(subscription_id:, name: nil, group_level: nil)
        attributes = {}
        attributes[:name] = name if name
        attributes[:groupLevel] = group_level if group_level

        return nil if attributes.empty?

        patch("/subscriptions/#{subscription_id}", body: {
                data: {
                  type: 'subscriptions',
                  id: subscription_id,
                  attributes: attributes
                }
              })
      end

      # Update subscription localization (display name and description)
      def update_subscription_localization(localization_id:, name: nil, description: nil)
        attributes = {}
        attributes[:name] = name if name
        attributes[:description] = description if description

        return nil if attributes.empty?

        patch("/subscriptionLocalizations/#{localization_id}", body: {
                data: {
                  type: 'subscriptionLocalizations',
                  id: localization_id,
                  attributes: attributes
                }
              })
      end
    end
  end
end
