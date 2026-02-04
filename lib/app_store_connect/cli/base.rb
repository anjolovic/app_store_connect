# frozen_string_literal: true

module AppStoreConnect
  class CLI
    # Shared helpers for CLI command modules
    module Base
      private

      def global_options
        instance_variable_get(:@global_options) || {}
      end

      def client
        @client ||= Client.new
      end

      def json?
        !!global_options[:json]
      end

      def quiet?
        !!global_options[:quiet]
      end

      def verbose?
        !!global_options[:verbose]
      end

      def no_color?
        ENV['NO_COLOR'] == '1'
      end

      def output_json(obj)
        require 'json'
        puts JSON.pretty_generate(obj)
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
