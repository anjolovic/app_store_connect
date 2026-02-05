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

      # Get subscription availability (territories)
      def subscription_availability(subscription_id:)
        result = get("/subscriptions/#{subscription_id}/subscriptionAvailability?include=availableTerritories")
        availability = result['data']
        return nil unless availability

        territories = (result['included'] || []).select { |item| item['type'] == 'territories' }.map do |territory|
          {
            id: territory['id'],
            currency: territory.dig('attributes', 'currency')
          }
        end

        {
          id: availability['id'],
          available_in_new_territories: availability.dig('attributes', 'availableInNewTerritories'),
          territories: territories
        }
      rescue ApiError => e
        return nil if e.message.include?('Not found')

        raise
      end

      # Create subscription availability
      def create_subscription_availability(subscription_id:, territory_ids: [], available_in_new_territories: nil)
        body = {
          data: {
            type: 'subscriptionAvailabilities',
            attributes: {},
            relationships: {
              subscription: {
                data: { type: 'subscriptions', id: subscription_id }
              },
              availableTerritories: {
                data: territory_ids.map { |id| { type: 'territories', id: id } }
              }
            }
          }
        }
        body[:data][:attributes][:availableInNewTerritories] = available_in_new_territories unless available_in_new_territories.nil?
        body[:data].delete(:attributes) if body[:data][:attributes].empty?

        result = post('/subscriptionAvailabilities', body: body)['data']
        {
          id: result['id']
        }
      end

      # Update subscription availability territories
      def update_subscription_availability(availability_id:, territory_ids:)
        patch("/subscriptionAvailabilities/#{availability_id}/relationships/availableTerritories", body: {
                data: territory_ids.map { |id| { type: 'territories', id: id } }
              })
      end

      # Update subscription availability attributes
      def update_subscription_availability_attributes(availability_id:, available_in_new_territories:)
        patch("/subscriptionAvailabilities/#{availability_id}", body: {
                data: {
                  type: 'subscriptionAvailabilities',
                  id: availability_id,
                  attributes: {
                    availableInNewTerritories: available_in_new_territories
                  }
                }
              })
      end

      # List subscription introductory offers
      def subscription_introductory_offers(subscription_id:)
        get("/subscriptions/#{subscription_id}/subscriptionIntroductoryOffers")['data'].map do |offer|
          {
            id: offer['id'],
            offer_mode: offer.dig('attributes', 'offerMode'),
            duration: offer.dig('attributes', 'duration'),
            number_of_periods: offer.dig('attributes', 'numberOfPeriods'),
            start_date: offer.dig('attributes', 'startDate'),
            end_date: offer.dig('attributes', 'endDate'),
            price_point_id: offer.dig('relationships', 'subscriptionPricePoint', 'data', 'id')
          }
        end
      end

      # Delete a subscription introductory offer
      def delete_subscription_introductory_offer(offer_id:)
        delete("/subscriptionIntroductoryOffers/#{offer_id}")
      end

      # Get subscription images
      def subscription_images(subscription_id:)
        data =
          begin
            get("/subscriptions/#{subscription_id}/images")['data']
          rescue ApiError => e
            # Older/alternate API path
            if e.message.include?('Not found')
              get("/subscriptions/#{subscription_id}/subscriptionImages")['data']
            else
              raise
            end
          end

        (data || []).map do |image|
          {
            id: image['id'],
            file_name: image.dig('attributes', 'fileName'),
            file_size: image.dig('attributes', 'fileSize'),
            upload_state: image.dig('attributes', 'state') || image.dig('attributes', 'assetDeliveryState', 'state'),
            source_file_checksum: image.dig('attributes', 'sourceFileChecksum')
          }
        end
      rescue ApiError => e
        # If neither path is available, treat as "no images" to avoid blocking metadata checks.
        return [] if e.message.include?('Not found')

        raise
      end

      # Get a specific subscription image by ID
      def subscription_image(image_id:)
        image = get("/subscriptionImages/#{image_id}")['data']
        return nil unless image

        {
          id: image['id'],
          file_name: image.dig('attributes', 'fileName'),
          file_size: image.dig('attributes', 'fileSize'),
          upload_state: image.dig('attributes', 'state') || image.dig('attributes', 'assetDeliveryState', 'state'),
          source_file_checksum: image.dig('attributes', 'sourceFileChecksum')
        }
      rescue ApiError => e
        return nil if e.message.include?('Not found')

        raise
      end

      # Upload a subscription image (1024x1024)
      def upload_subscription_image(subscription_id:, file_path:)
        file_name = File.basename(file_path)
        file_size = File.size(file_path)
        checksum = Digest::MD5.file(file_path).base64digest

        reservation = post('/subscriptionImages', body: {
                             data: {
                               type: 'subscriptionImages',
                               attributes: {
                                 fileName: file_name,
                                 fileSize: file_size
                               },
                               relationships: {
                                 subscription: {
                                   data: {
                                     type: 'subscriptions',
                                     id: subscription_id
                                   }
                                 }
                               }
                             }
                           })

        image_id = reservation['data']['id']
        upload_operations = reservation['data'].dig('attributes', 'uploadOperations')

        file_data = File.binread(file_path)
        upload_operations&.each do |operation|
          upload_part(
            url: operation['url'],
            data: file_data[operation['offset'], operation['length']],
            headers: operation['requestHeaders']
          )
        end

        patch("/subscriptionImages/#{image_id}", body: {
                data: {
                  type: 'subscriptionImages',
                  id: image_id,
                  attributes: {
                    uploaded: true,
                    sourceFileChecksum: checksum
                  }
                }
              })

        reservation
      end

      # Delete a subscription image
      def delete_subscription_image(image_id:)
        delete("/subscriptionImages/#{image_id}")
      end

      # Get subscription App Store review screenshot
      def subscription_review_screenshot(subscription_id:)
        result = get("/subscriptions/#{subscription_id}/appStoreReviewScreenshot")['data']
        return nil unless result

        {
          id: result['id'],
          file_name: result.dig('attributes', 'fileName'),
          file_size: result.dig('attributes', 'fileSize'),
          upload_state: result.dig('attributes', 'assetDeliveryState', 'state'),
          source_file_checksum: result.dig('attributes', 'sourceFileChecksum')
        }
      rescue ApiError => e
        return nil if e.message.include?('Not found')

        raise
      end

      # Get a specific subscription App Store review screenshot by ID
      def subscription_review_screenshot_by_id(screenshot_id:)
        result = get("/subscriptionAppStoreReviewScreenshots/#{screenshot_id}")['data']
        return nil unless result

        {
          id: result['id'],
          file_name: result.dig('attributes', 'fileName'),
          file_size: result.dig('attributes', 'fileSize'),
          upload_state: result.dig('attributes', 'assetDeliveryState', 'state'),
          source_file_checksum: result.dig('attributes', 'sourceFileChecksum')
        }
      rescue ApiError => e
        return nil if e.message.include?('Not found')

        raise
      end

      # Upload a subscription App Store review screenshot
      def upload_subscription_review_screenshot(subscription_id:, file_path:)
        file_name = File.basename(file_path)
        file_size = File.size(file_path)
        checksum = Digest::MD5.file(file_path).base64digest

        reservation = post('/subscriptionAppStoreReviewScreenshots', body: {
                             data: {
                               type: 'subscriptionAppStoreReviewScreenshots',
                               attributes: {
                                 fileName: file_name,
                                 fileSize: file_size
                               },
                               relationships: {
                                 subscription: {
                                   data: {
                                     type: 'subscriptions',
                                     id: subscription_id
                                   }
                                 }
                               }
                             }
                           })

        screenshot_id = reservation['data']['id']
        upload_operations = reservation['data'].dig('attributes', 'uploadOperations')

        file_data = File.binread(file_path)
        upload_operations&.each do |operation|
          upload_part(
            url: operation['url'],
            data: file_data[operation['offset'], operation['length']],
            headers: operation['requestHeaders']
          )
        end

        patch("/subscriptionAppStoreReviewScreenshots/#{screenshot_id}", body: {
                data: {
                  type: 'subscriptionAppStoreReviewScreenshots',
                  id: screenshot_id,
                  attributes: {
                    uploaded: true,
                    sourceFileChecksum: checksum
                  }
                }
              })

        reservation
      end

      # Delete a subscription App Store review screenshot
      def delete_subscription_review_screenshot(screenshot_id:)
        delete("/subscriptionAppStoreReviewScreenshots/#{screenshot_id}")
      end

      # Update subscription tax category
      def update_subscription_tax_category(subscription_id:, tax_category_id:)
        patch("/subscriptions/#{subscription_id}/relationships/taxCategory", body: {
                data: {
                  type: 'taxCategories',
                  id: tax_category_id
                }
              })
      rescue ApiError => e
        if e.message.include?('Not found')
          raise ApiError,
                'Tax category is not available via ASC API for this account (endpoint returned 404). ' \
                'Set tax category in App Store Connect UI.'
        end

        raise
      end

      # List available tax categories
      def tax_categories(limit: 200)
        response = get('/taxCategories', params: { 'limit' => limit })
        response['data'].map do |category|
          {
            id: category['id'],
            name: category.dig('attributes', 'name')
          }
        end
      rescue ApiError => e
        if e.message.include?('Not found') && @app_id
          begin
            response = get("/apps/#{@app_id}/taxCategories", params: { 'limit' => limit })
            response['data'].map do |category|
              {
                id: category['id'],
                name: category.dig('attributes', 'name')
              }
            end
          rescue ApiError => inner
            if inner.message.include?('Not found')
              raise ApiError,
                    'Tax categories endpoint not available (global and app-scoped endpoints returned 404). ' \
                    'Set tax category in App Store Connect UI.'
            end
            raise
          end
        elsif e.message.include?('Not found')
          raise ApiError,
                'Tax categories endpoint not available. Set APP_STORE_CONNECT_APP_ID to use /apps/{app_id}/taxCategories.'
        else
          raise
        end
      end

      # Get subscription tax category (best-effort; may be unavailable via API)
      def subscription_tax_category(subscription_id:)
        result = get("/subscriptions/#{subscription_id}", params: { 'include' => 'taxCategory' })
        rel = result.dig('data', 'relationships', 'taxCategory', 'data')
        return nil unless rel && rel['id']

        included = (result['included'] || []).find do |item|
          item['type'] == 'taxCategories' && item['id'] == rel['id']
        end

        {
          id: rel['id'],
          name: included&.dig('attributes', 'name')
        }
      end

      # Submit a subscription group for review
      def submit_subscription_group(group_id:)
        result = post('/subscriptionGroupSubmissions', body: {
                        data: {
                          type: 'subscriptionGroupSubmissions',
                          relationships: {
                            subscriptionGroup: {
                              data: { type: 'subscriptionGroups', id: group_id }
                            }
                          }
                        }
                      })['data']

        {
          id: result['id'],
          state: result.dig('attributes', 'state'),
          created_date: result.dig('attributes', 'createdDate')
        }
      end

      # List submissions for a subscription group
      def subscription_group_submissions(group_id:)
        get("/subscriptionGroups/#{group_id}/subscriptionGroupSubmissions")['data'].map do |sub|
          {
            id: sub['id'],
            state: sub.dig('attributes', 'state'),
            created_date: sub.dig('attributes', 'createdDate')
          }
        end
      end

      # List subscription group localizations (name per locale)
      def subscription_group_localizations(group_id:)
        get("/subscriptionGroups/#{group_id}/subscriptionGroupLocalizations")['data'].map do |loc|
          {
            id: loc['id'],
            locale: loc.dig('attributes', 'locale'),
            name: loc.dig('attributes', 'name')
          }
        end
      rescue ApiError => e
        return [] if e.message.include?('Not found')

        raise
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
