# frozen_string_literal: true

module AppStoreConnect
  class CLI
    # Shared helpers for CLI command modules
    module Base
      private

      def client
        @client ||= Client.new
      end

      def find_active_phased_release
        versions = client.app_store_versions
        active_version = versions.find { |v| v.dig('attributes', 'appStoreState') == 'READY_FOR_SALE' }

        unless active_version
          puts "\e[31mNo version currently released.\e[0m"
          return nil
        end

        version_id = active_version['id']
        phased = client.phased_release(version_id: version_id)

        unless phased
          puts "\e[31mNo phased release found for current version.\e[0m"
          return nil
        end

        phased
      end
    end
  end
end
