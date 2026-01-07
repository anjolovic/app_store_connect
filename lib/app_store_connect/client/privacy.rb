# frozen_string_literal: true

module AppStoreConnect
  class Client
    # App privacy and data usage methods
    module Privacy
      # Get app data usage declarations (privacy labels)
      def app_data_usages(target_app_id: nil)
        target_app_id ||= @app_id
        result = get("/apps/#{target_app_id}/appDataUsages?include=dataProtection")

        usages = result['data'] || []
        included = result['included'] || []

        usages.map do |usage|
          protection_id = usage.dig('relationships', 'dataProtection', 'data', 'id')
          protection = included.find { |i| i['type'] == 'appDataUsageDataProtections' && i['id'] == protection_id }

          {
            id: usage['id'],
            category: usage.dig('attributes', 'category'),
            purposes: extract_purposes(usage),
            data_protection: protection&.dig('attributes', 'dataProtection')
          }
        end
      rescue ApiError => e
        return [] if e.message.include?('Not found')

        raise
      end

      # Create an app data usage declaration
      def create_app_data_usage(category:, purposes:, data_protection: nil, target_app_id: nil)
        target_app_id ||= @app_id

        body = {
          data: {
            type: 'appDataUsages',
            attributes: {
              category: category
            },
            relationships: {
              app: {
                data: {
                  type: 'apps',
                  id: target_app_id
                }
              }
            }
          }
        }

        # Add purposes if provided
        if purposes&.any?
          body[:data][:relationships][:purposes] = {
            data: purposes.map { |p| { type: 'appDataUsagePurposes', id: p } }
          }
        end

        # Add data protection if provided
        if data_protection
          body[:data][:relationships][:dataProtection] = {
            data: { type: 'appDataUsageDataProtections', id: data_protection }
          }
        end

        post('/appDataUsages', body: body)
      end

      # Delete an app data usage declaration
      def delete_app_data_usage(usage_id:)
        delete("/appDataUsages/#{usage_id}")
      end

      private

      def extract_purposes(usage)
        purposes_data = usage.dig('relationships', 'purposes', 'data')
        return [] unless purposes_data

        purposes_data.map { |p| p['id'] }
      end
    end
  end
end
