# frozen_string_literal: true

module AppStoreConnect
  class Client
    # Pricing and availability methods
    module Pricing
      # Get subscription price points for a territory
      def subscription_price_points(subscription_id:, territory: 'USA')
        get("/subscriptions/#{subscription_id}/pricePoints?filter[territory]=#{territory}&include=territory")['data']
      end

      # Get current subscription prices
      def subscription_prices(subscription_id:)
        get("/subscriptions/#{subscription_id}/prices?include=subscriptionPricePoint")['data'].map do |price|
          {
            id: price['id'],
            start_date: price.dig('attributes', 'startDate'),
            preserved: price.dig('attributes', 'preserved'),
            price_point_id: price.dig('relationships', 'subscriptionPricePoint', 'data', 'id')
          }
        end
      end

      # Get app price schedule (current and future prices)
      def app_price_schedule(target_app_id: nil)
        target_app_id ||= @app_id
        result = get("/apps/#{target_app_id}/appPriceSchedule?include=manualPrices,automaticPrices,baseTerritory")

        schedule = result['data']
        included = result['included'] || []

        base_territory_id = schedule.dig('relationships', 'baseTerritory', 'data', 'id')
        base_territory = included.find { |i| i['type'] == 'territories' && i['id'] == base_territory_id }

        manual_price_ids = schedule.dig('relationships', 'manualPrices', 'data')&.map { |p| p['id'] } || []
        manual_prices = included.select { |i| i['type'] == 'appPrices' && manual_price_ids.include?(i['id']) }

        {
          id: schedule['id'],
          base_territory: base_territory&.dig('attributes', 'currency'),
          manual_prices: manual_prices.map do |price|
            {
              id: price['id'],
              start_date: price.dig('attributes', 'startDate'),
              end_date: price.dig('attributes', 'endDate')
            }
          end
        }
      rescue ApiError => e
        return nil if e.message.include?('Not found')

        raise
      end

      # Get available price points for a territory
      def app_price_points(target_app_id: nil, territory: 'USA', limit: 50)
        target_app_id ||= @app_id
        get("/apps/#{target_app_id}/appPricePoints?filter[territory]=#{territory}&limit=#{limit}")['data'].map do |point|
          {
            id: point['id'],
            customer_price: point.dig('attributes', 'customerPrice'),
            proceeds: point.dig('attributes', 'proceeds')
          }
        end
      end

      # Get app availability (territories where app is available)
      def app_availability(target_app_id: nil)
        target_app_id ||= @app_id
        result = get("/apps/#{target_app_id}/appAvailability?include=availableTerritories")

        availability = result['data']
        included = result['included'] || []

        territories_data = included.select { |i| i['type'] == 'territories' }

        {
          id: availability['id'],
          available_in_new_territories: availability.dig('attributes', 'availableInNewTerritories'),
          territories: territories_data.map do |t|
            {
              id: t['id'],
              currency: t.dig('attributes', 'currency')
            }
          end
        }
      rescue ApiError => e
        return nil if e.message.include?('Not found')

        raise
      end

      # List all territories
      def territories(limit: 200)
        get("/territories?limit=#{limit}")['data'].map do |t|
          {
            id: t['id'],
            currency: t.dig('attributes', 'currency')
          }
        end
      end

      # Update app availability (set available_in_new_territories)
      def update_app_availability(availability_id:, available_in_new_territories:)
        patch("/appAvailabilities/#{availability_id}", body: {
                data: {
                  type: 'appAvailabilities',
                  id: availability_id,
                  attributes: {
                    availableInNewTerritories: available_in_new_territories
                  }
                }
              })
      end
    end
  end
end
