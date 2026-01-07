# frozen_string_literal: true

module AppStoreConnect
  class Client
    # In-App Purchase management methods
    module InAppPurchases
      # Get all in-app purchases for an app
      def in_app_purchases(target_app_id: nil)
        target_app_id ||= @app_id
        get("/apps/#{target_app_id}/inAppPurchasesV2")['data'].map do |iap|
          {
            id: iap['id'],
            product_id: iap.dig('attributes', 'productId'),
            name: iap.dig('attributes', 'name'),
            state: iap.dig('attributes', 'state'),
            type: iap.dig('attributes', 'inAppPurchaseType'),
            review_note: iap.dig('attributes', 'reviewNote')
          }
        end
      end

      # Get a single in-app purchase by ID
      def in_app_purchase(iap_id:)
        iap = get("/inAppPurchasesV2/#{iap_id}")['data']
        {
          id: iap['id'],
          product_id: iap.dig('attributes', 'productId'),
          name: iap.dig('attributes', 'name'),
          state: iap.dig('attributes', 'state'),
          type: iap.dig('attributes', 'inAppPurchaseType'),
          review_note: iap.dig('attributes', 'reviewNote')
        }
      end

      # Get in-app purchase localizations
      def in_app_purchase_localizations(iap_id:)
        get("/inAppPurchasesV2/#{iap_id}/inAppPurchaseLocalizations")['data'].map do |loc|
          {
            id: loc['id'],
            locale: loc.dig('attributes', 'locale'),
            name: loc.dig('attributes', 'name'),
            description: loc.dig('attributes', 'description'),
            state: loc.dig('attributes', 'state')
          }
        end
      end

      # Update in-app purchase metadata (name, review note)
      def update_in_app_purchase(iap_id:, name: nil, review_note: nil)
        attributes = {}
        attributes[:name] = name if name
        attributes[:reviewNote] = review_note if review_note

        return nil if attributes.empty?

        patch("/inAppPurchasesV2/#{iap_id}", body: {
                data: {
                  type: 'inAppPurchases',
                  id: iap_id,
                  attributes: attributes
                }
              })
      end

      # Create a new in-app purchase localization
      def create_in_app_purchase_localization(iap_id:, locale:, name:, description: nil)
        attributes = {
          locale: locale,
          name: name
        }
        attributes[:description] = description if description

        post('/inAppPurchaseLocalizations', body: {
               data: {
                 type: 'inAppPurchaseLocalizations',
                 attributes: attributes,
                 relationships: {
                   inAppPurchaseV2: {
                     data: {
                       type: 'inAppPurchases',
                       id: iap_id
                     }
                   }
                 }
               }
             })
      end

      # Update in-app purchase localization (display name/description users see)
      def update_in_app_purchase_localization(localization_id:, name: nil, description: nil)
        attributes = {}
        attributes[:name] = name if name
        attributes[:description] = description if description

        return nil if attributes.empty?

        patch("/inAppPurchaseLocalizations/#{localization_id}", body: {
                data: {
                  type: 'inAppPurchaseLocalizations',
                  id: localization_id,
                  attributes: attributes
                }
              })
      end

      # Delete an in-app purchase localization
      def delete_in_app_purchase_localization(localization_id:)
        delete("/inAppPurchaseLocalizations/#{localization_id}")
      end

      # Submit in-app purchase for review
      def submit_in_app_purchase(iap_id:)
        post('/inAppPurchaseSubmissions', body: {
               data: {
                 type: 'inAppPurchaseSubmissions',
                 relationships: {
                   inAppPurchaseV2: {
                     data: {
                       type: 'inAppPurchases',
                       id: iap_id
                     }
                   }
                 }
               }
             })
      end
    end
  end
end
