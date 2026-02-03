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

      # Create a subscription group
      def create_subscription_group(reference_name:, target_app_id: nil)
        target_app_id ||= @app_id
        body = {
          data: {
            type: 'subscriptionGroups',
            attributes: {
              referenceName: reference_name
            },
            relationships: {
              app: {
                data: { type: 'apps', id: target_app_id }
              }
            }
          }
        }

        result = post('/subscriptionGroups', body: body)['data']
        {
          id: result['id'],
          reference_name: result.dig('attributes', 'referenceName')
        }
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

      # Create a subscription
      def create_subscription(subscription_group_id:, name:, product_id:, subscription_period:,
                              family_sharable: nil, review_note: nil, group_level: nil)
        attributes = {
          name: name,
          productId: product_id,
          subscriptionPeriod: subscription_period
        }
        attributes[:familySharable] = family_sharable unless family_sharable.nil?
        attributes[:reviewNote] = review_note if review_note
        attributes[:groupLevel] = group_level if group_level

        body = {
          data: {
            type: 'subscriptions',
            attributes: attributes,
            relationships: {
              group: {
                data: { type: 'subscriptionGroups', id: subscription_group_id }
              }
            }
          }
        }

        result = post('/subscriptions', body: body)['data']
        {
          id: result['id'],
          name: result.dig('attributes', 'name'),
          product_id: result.dig('attributes', 'productId'),
          state: result.dig('attributes', 'state'),
          group_level: result.dig('attributes', 'groupLevel'),
          subscription_period: result.dig('attributes', 'subscriptionPeriod')
        }
      end

      # Create an introductory offer for a subscription
      def create_subscription_introductory_offer(subscription_id:, offer_mode:, duration:, subscription_price_point_id:)
        body = {
          data: {
            type: 'subscriptionIntroductoryOffers',
            attributes: {
              offerMode: offer_mode,
              duration: duration
            },
            relationships: {
              subscription: {
                data: { type: 'subscriptions', id: subscription_id }
              },
              subscriptionPricePoint: {
                data: { type: 'subscriptionPricePoints', id: subscription_price_point_id }
              }
            }
          }
        }

        result = post('/subscriptionIntroductoryOffers', body: body)['data']
        {
          id: result['id'],
          offer_mode: result.dig('attributes', 'offerMode'),
          duration: result.dig('attributes', 'duration'),
          price_point_id: result.dig('relationships', 'subscriptionPricePoint', 'data', 'id')
        }
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
