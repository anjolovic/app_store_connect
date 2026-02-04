# frozen_string_literal: true

require_relative 'cli/base'
require_relative 'cli/help'
require_relative 'cli/apps'
require_relative 'cli/review'
require_relative 'cli/versions'
require_relative 'cli/subscriptions'
require_relative 'cli/in_app_purchases'
require_relative 'cli/customer_reviews'
require_relative 'cli/screenshots'
require_relative 'cli/releases'
require_relative 'cli/test_flight'
require_relative 'cli/admin'
require_relative 'cli/users'
require_relative 'cli/privacy'

module AppStoreConnect
  # Command-line interface for App Store Connect API
  #
  # Usage:
  #   asc status      # Full app status summary
  #   asc review      # Check review submission status
  #   asc subs        # List subscription products
  #   asc builds      # List recent builds
  #   asc apps        # List all apps
  #   asc ready       # Check if ready for submission
  #   asc help        # Show help
  #
  class CLI
    include Base
    include Help
    include Apps
    include Review
    include Versions
    include Subscriptions
    include InAppPurchases
    include CustomerReviews
    include Screenshots
    include Releases
    include TestFlight
    include Admin
    include Users
    include Privacy

    COMMANDS = %w[
      status review rejection session subs subscriptions builds apps ready help
      review-info update-review-notes update-review-contact update-demo-account
      cancel-review submit create-review-detail content-rights set-content-rights
      sub-details sub-metadata-status sub-ensure-assets create-sub create-subscription fix-sub-metadata
      sub-availability set-sub-availability
      sub-price-points sub-prices add-sub-price
      sub-image upload-sub-image delete-sub-image
      sub-review-screenshot upload-sub-review-screenshot delete-sub-review-screenshot
      set-sub-tax-category tax-categories
      sub-localizations update-sub-localization
      sub-intro-offers delete-sub-intro-offer
      update-sub-description update-sub-note delete-sub
      version-info update-whats-new description update-description
      keywords update-keywords urls update-marketing-url update-support-url
      update-promotional-text update-privacy-url
      iaps iap-details update-iap-note update-iap-description submit-iap
      customer-reviews respond-review
      upload-iap-screenshot delete-iap-screenshot
      screenshots upload-screenshot upload-screenshots delete-screenshot
      create-version release phased-release pause-release resume-release
      complete-release enable-phased-release
      pre-order enable-pre-order cancel-pre-order
      testers tester-groups add-tester remove-tester
      create-group delete-group group-testers add-to-group remove-from-group
      testflight-builds distribute-build remove-build
      beta-whats-new update-beta-whats-new submit-beta-review beta-review-status
      app-info age-rating categories update-app-name update-subtitle
      availability territories pricing
      users invitations invite-user remove-user cancel-invitation
      privacy-labels privacy-types privacy-purposes
    ].freeze

    def initialize(args)
      args = args.dup
      @global_options = parse_global_options!(args)

      @command = args.first || 'status'
      @options = args.drop(1)
    end

    def global_options
      @global_options ||= {}
    end

    def run
      unless COMMANDS.include?(@command)
        puts "Unknown command: #{@command}"
        puts "Run 'asc help' for usage"
        exit 1
      end

      send("cmd_#{@command.gsub('-', '_')}")
    rescue ConfigurationError => e
      puts "\e[31mConfiguration Error:\e[0m #{e.message}"
      puts
      puts "Run 'asc help' for setup instructions"
      exit 1
    rescue ApiError => e
      puts "\e[31mAPI Error:\e[0m #{e.message}"
      exit 1
    end

    private

    # Parse and remove global flags before command dispatch.
    # Keep this conservative to avoid breaking per-command parsing.
    def parse_global_options!(args)
      opts = {
        json: false,
        no_color: false,
        quiet: false,
        verbose: false
      }

      consumed = []
      args.each_with_index do |arg, idx|
        case arg
        when '--json'
          opts[:json] = true
          consumed << idx
        when '--no-color'
          opts[:no_color] = true
          consumed << idx
        when '--quiet'
          opts[:quiet] = true
          consumed << idx
        when '--verbose'
          opts[:verbose] = true
          consumed << idx
        end
      end

      consumed.sort.reverse.each { |idx| args.delete_at(idx) }

      # Provide a standard opt-out for ANSI colors.
      ENV['NO_COLOR'] = '1' if opts[:no_color]

      opts
    end
  end
end
