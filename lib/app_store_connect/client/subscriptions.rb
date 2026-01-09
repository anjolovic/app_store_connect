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

      # Get subscription localizations
      def subscription_localizations(subscription_id:)
        get("/subscriptions/#{subscription_id}/subscriptionLocalizations")['data'].map do |loc|
          {
            id: loc['id'],
            locale: loc.dig('attributes', 'locale'),
            name: loc.dig('attributes', 'name'),
            description: loc.dig('attributes', 'description')
          }
        end
      end

      # Create subscription localization
      def create_subscription_localization(subscription_id:, locale:, name:, description: nil)
        body = {
          data: {
            type: 'subscriptionLocalizations',
            attributes: {
              locale: locale,
              name: name
            },
            relationships: {
              subscription: {
                data: { type: 'subscriptions', id: subscription_id }
              }
            }
          }
        }
        body[:data][:attributes][:description] = description if description

        post('/subscriptionLocalizations', body: body)
      end

      # Update subscription metadata (name, group level, review note)
      def update_subscription(subscription_id:, name: nil, group_level: nil, review_note: nil)
        attributes = {}
        attributes[:name] = name if name
        attributes[:groupLevel] = group_level if group_level
        attributes[:reviewNote] = review_note if review_note

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

      # Delete a subscription
      # Note: Can only delete subscriptions that have never been submitted for review
      def delete_subscription(subscription_id:)
        delete("/subscriptions/#{subscription_id}")
      end

      # Delete a subscription group
      # Note: Can only delete empty groups (no subscriptions)
      def delete_subscription_group(group_id:)
        delete("/subscriptionGroups/#{group_id}")
      end
    end
  end
end
