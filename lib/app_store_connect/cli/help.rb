# frozen_string_literal: true

module AppStoreConnect
  class CLI
    # Help command
    module Help
      def cmd_help
        puts <<~HELP
          \e[1mApp Store Connect CLI\e[0m

          A command-line tool for checking and updating App Store Connect.

          \e[1mUSAGE:\e[0m
            asc <command> [options]

          \e[1mREAD COMMANDS:\e[0m
            status            Full app status summary (default)
            review            Check review submission status
            rejection         Show rejection details and messages
            session           Check session status for Resolution Center
            review-info       Show review contact info and notes
            subs              List subscription products
            sub-details       Detailed subscription info with localizations
            sub-availability  Show subscription availability territories
            sub-price-points  List subscription price points for territory (limit-based pagination)
            sub-prices        Show subscription price schedule
            sub-image         Show subscription image
            sub-review-screenshot  Show subscription review screenshot
            sub-localizations List subscription localizations
            sub-intro-offers  List subscription introductory offers
            iaps              List in-app purchases
            iap-details       Detailed IAP info with localizations
            version-info      Show version localizations (description, what's new)
            screenshots       List app screenshots for current version
            builds            List recent builds
            apps              List all apps in your account
            ready             Check if ready for submission
            customer-reviews  List recent customer reviews

          \e[1mAPP METADATA:\e[0m
            description [locale]                  Show app description
            update-description <locale> "text"    Update app description
            keywords [locale]                     Show app keywords
            update-keywords <locale> "words"      Update keywords (100 char limit)
            urls [locale]                         Show marketing/support URLs
            update-marketing-url <locale> <url>   Update marketing URL
            update-support-url <locale> <url>     Update support URL
            update-promotional-text <locale> "text"  Update promotional text
            update-privacy-url <locale> <url>     Update privacy policy URL

          \e[1mWRITE COMMANDS (respond to Apple Review requests):\e[0m
            update-review-notes "notes"           Update notes for App Review
            update-review-contact [options]       Update App Review contact info
            update-demo-account [options]         Set demo account for App Review
            update-whats-new "text"               Update "What's New" release notes
            create-review-detail                  Create review detail for version
            content-rights                        Show content rights declaration status
            set-content-rights <yes|no>           Declare third-party content usage
            create-sub <product_id> "name" <period>  Create subscription product
            update-sub-description <id> "desc"    Update subscription description
            update-sub-note <id> "note"           Update subscription review note
            fix-sub-metadata <id> [options]       Add missing subscription metadata
            set-sub-availability <id> <territories...>  Set subscription availability (requires --available-in-new-territories on first set)
            add-sub-price <id> <price_point_id>   Add subscription price schedule
            upload-sub-image <id> <file>          Upload subscription image (1024x1024)
            delete-sub-image <id>                 Delete subscription image
            upload-sub-review-screenshot <id> <file> Upload subscription review screenshot
            delete-sub-review-screenshot <id>     Delete subscription review screenshot
            set-sub-tax-category <id> <tax_id>    Update subscription tax category
            tax-categories [limit]               List available tax categories
            update-sub-localization <id> <locale> Update or create localization
            delete-sub-intro-offer <offer_id>     Delete introductory offer
            delete-sub <product_id>               Delete a draft subscription
            update-iap-note <id> "note"           Update IAP review notes
            update-iap-description <id> "desc"    Update IAP description
            submit-iap <product_id>               Submit IAP for review
            respond-review <id> "response"        Respond to a customer review
            submit                                Submit version for App Review
            cancel-review                         Cancel pending review submission

          \e[1mSCREENSHOT COMMANDS:\e[0m
            upload-iap-screenshot <id> <file>     Upload IAP review screenshot
            delete-iap-screenshot <id>            Delete IAP review screenshot
            upload-screenshot <type> <locale> <file>  Upload app screenshot
            upload-screenshots <locale> <dir>    Batch upload from directory
            delete-screenshot <id>                Delete app screenshot
            upload-sub-image <id> <file>          Upload subscription image
            delete-sub-image <id>                 Delete subscription image
            upload-sub-review-screenshot <id> <file> Upload subscription review screenshot
            delete-sub-review-screenshot <id>     Delete subscription review screenshot

          \e[1mRELEASE AUTOMATION:\e[0m
            create-version <version> [type]       Create new app version
            release                               Release pending version to App Store
            phased-release                        Show phased release status
            enable-phased-release                 Enable 7-day gradual rollout
            pause-release                         Pause phased release
            resume-release                        Resume phased release
            complete-release                      Release to all users immediately
            pre-order                             Show pre-order status
            enable-pre-order <date>               Enable pre-orders (YYYY-MM-DD)
            cancel-pre-order                      Cancel pre-orders

          \e[1mTESTFLIGHT:\e[0m
            testers                               List beta testers
            tester-groups                         List beta groups
            add-tester <email> [name] [groups]    Add a beta tester
            remove-tester <tester_id>             Remove a beta tester
            create-group <name> [--public]        Create a beta group
            delete-group <group_id>               Delete a beta group
            group-testers <group_id>              List testers in a group
            add-to-group <group_id> <testers>     Add testers to a group
            remove-from-group <group> <testers>   Remove testers from group
            testflight-builds                     List TestFlight builds
            distribute-build <build> <groups>     Add build to groups
            remove-build <build> <groups>         Remove build from groups
            beta-whats-new <build_id>             Show What's New for build
            update-beta-whats-new <build> "text"  Update What's New text
            submit-beta-review <build_id>         Submit build for beta review
            beta-review-status <build_id>         Check beta review status

          \e[1mAPP ADMINISTRATION:\e[0m
            app-info                              Show app info and localizations
            age-rating                            Show age rating declaration
            categories [platform]                 List available categories
            update-app-name "name"                Update app name
            update-subtitle "subtitle"            Update app subtitle
            availability                          Show app territory availability
            territories                           List all territories
            pricing                               Show app pricing info

          \e[1mAPP PRIVACY (reference only - API not supported):\e[0m
            privacy-labels                        Info on completing privacy questionnaire
            privacy-types                         Reference: all data types by category
            privacy-purposes                      Reference: all purpose definitions

          \e[1mUSER MANAGEMENT:\e[0m
            users                                 List team users
            invitations                           List pending invitations
            invite-user <email> <name> <roles>    Invite a new user
            remove-user <user_id>                 Remove user from team
            cancel-invitation <id>                Cancel pending invitation

            help              Show this help message

          \e[1mSETUP:\e[0m

          1. Generate an App Store Connect API key:
             - Go to https://appstoreconnect.apple.com
             - Navigate to Users and Access > Integrations > App Store Connect API
             - Click "Generate API Key"
             - Select role: Admin or App Manager
             - Download the .p8 file (you can only download once!)
             - Note the Key ID shown

          2. Set environment variables:

             APP_STORE_CONNECT_KEY_ID=YOUR_KEY_ID
             APP_STORE_CONNECT_ISSUER_ID=YOUR_ISSUER_ID
             APP_STORE_CONNECT_PRIVATE_KEY_PATH=/path/to/AuthKey_XXXX.p8
             APP_STORE_CONNECT_APP_ID=YOUR_APP_ID
             APP_STORE_CONNECT_BUNDLE_ID=com.example.app

             Note: The Issuer ID is the same for all keys in your team.
             It's shown at the top of the App Store Connect API keys page.

          3. Move your .p8 key to a secure location:
             mkdir -p ~/.config/app_store_connect/keys
             mv AuthKey_XXXX.p8 ~/.config/app_store_connect/keys/
             chmod 600 ~/.config/app_store_connect/keys/AuthKey_XXXX.p8

          \e[1mRESOLUTION CENTER (optional):\e[0m

          To access rejection messages from Apple's Resolution Center, you need
          a web session. This uses fastlane's authentication:

          1. Install fastlane:
             gem install fastlane

          2. Generate a session:
             fastlane spaceauth -u your@apple.id

          3. Copy the session string and set the environment variable:
             export FASTLANE_SESSION="---\\n- ..."

          4. Verify session is working:
             asc session

          Note: Sessions expire after ~30 days. Re-run spaceauth when expired.
          Without a session, `asc rejection` shows status but not Apple's message.

          \e[1mEXAMPLES:\e[0m
            asc                           # Show full status
            asc review-info               # View review details
            asc update-review-notes "Please test with demo account"
            asc update-whats-new "Bug fixes and performance improvements"
            asc sub-details               # View subscription localizations
            asc create-sub com.example.app.plan.monthly "Monthly Plan" 1m --group "Main Plans" --create-group
            asc iap-details               # View IAP localizations
            asc customer-reviews          # View recent customer reviews

          \e[1mRESPONDING TO APPLE REVIEW:\e[0m
            # If Apple requests contact info (required before review notes):
            asc update-review-contact --first-name John --last-name Doe --email john@example.com --phone "+1234567890"

            # If your app requires sign-in, set demo account credentials:
            asc update-demo-account --username demo@example.com --password secret123 --required

            # Content rights declaration (required before submission):
            asc content-rights                     # Check current status
            asc set-content-rights no              # App doesn't use third-party content
            asc set-content-rights yes             # App uses third-party content (you have rights)

            # If Apple requests updated reviewer notes:
            asc update-review-notes "Use demo account: test@example.com / password123"

            # If Apple requests updated release notes:
            asc update-whats-new "Fixed subscription flow issues"

            # If Apple requests subscription description update:
            asc update-sub-description com.example.app.plan.starter.monthly "Access to basic features"

            # Fix subscription metadata (localization + price):
            asc fix-sub-metadata com.example.app.plan.starter.monthly --display-name "Starter Monthly" --description "Access basic features" --price-point PRICE_POINT_ID

            # Set availability and pricing:
            asc set-sub-availability com.example.app.plan.starter.monthly USA CAN GBR
            asc sub-price-points com.example.app.plan.starter.monthly USA
            asc add-sub-price com.example.app.plan.starter.monthly PRICE_POINT_ID --start-date 2026-03-01

            # Subscription assets:
            asc upload-sub-image com.example.app.plan.starter.monthly ~/Desktop/subscription.png
            asc upload-sub-review-screenshot com.example.app.plan.starter.monthly ~/Desktop/review.png
            asc tax-categories

            # Create subscription with price + intro offer:
            asc create-sub com.example.app.plan.monthly "Monthly Plan" 1m --group "Main Plans" --create-group --price-point PRICE_POINT_ID --intro-offer FREE_TRIAL --intro-duration 1w --intro-price-point INTRO_PRICE_POINT_ID

            # If Apple requests IAP metadata update:
            asc update-iap-note com.example.app.coins.100 "Unlocks 100 coins for gameplay"
            asc update-iap-description com.example.app.coins.100 "Get 100 coins to use in-game"

            # Respond to customer reviews:
            asc customer-reviews
            asc respond-review abc123 "Thank you for your feedback!"

          \e[1mSCREENSHOT MANAGEMENT:\e[0m
            # View current screenshots:
            asc screenshots

            # Upload IAP review screenshot:
            asc upload-iap-screenshot com.example.app.coins.100 ~/Desktop/iap-screenshot.png

            # Upload app screenshot (iPhone 6.7"):
            asc upload-screenshot APP_IPHONE_67 en-US ~/Desktop/screenshot.png

            # Delete a screenshot:
            asc delete-screenshot abc123

          \e[1mRELEASE AUTOMATION:\e[0m
            # Create a new version:
            asc create-version 2.0.0
            asc create-version 2.0.0 MANUAL    # Hold for manual release

            # Enable phased rollout (gradual 7-day release):
            asc enable-phased-release

            # Control phased release:
            asc phased-release                 # Check status
            asc pause-release                  # Pause if issues found
            asc resume-release                 # Resume rollout
            asc complete-release               # Release to all users now

            # Manual release (for MANUAL release type):
            asc release

            # Pre-orders:
            asc enable-pre-order 2025-06-01
            asc pre-order                      # Check status
            asc cancel-pre-order

          \e[1mTESTFLIGHT AUTOMATION:\e[0m
            # Manage beta testers:
            asc testers                        # List all testers
            asc add-tester test@example.com John Doe
            asc remove-tester tester_id

            # Manage beta groups:
            asc tester-groups                  # List groups
            asc create-group "External Testers"
            asc create-group "Public Beta" --public --limit 1000
            asc group-testers group_id         # See testers in group
            asc add-to-group group_id tester1 tester2

            # Distribute builds:
            asc testflight-builds              # List builds
            asc distribute-build build_id group_id
            asc update-beta-whats-new build_id "Bug fixes"

            # External beta review:
            asc submit-beta-review build_id
            asc beta-review-status build_id

          \e[1mAPP ADMINISTRATION:\e[0m
            # View app info and settings:
            asc app-info                       # App name, subtitle, privacy URL
            asc age-rating                     # Content ratings
            asc categories                     # Available categories

            # Update app metadata:
            asc update-app-name "My Awesome App"
            asc update-subtitle "The best app ever"

            # View availability and pricing:
            asc availability                   # Where app is available
            asc territories                    # All territories
            asc pricing                        # Price points

          \e[1mAPP PRIVACY (reference for web questionnaire):\e[0m
            # Apple's API does not support managing privacy declarations.
            # Complete the questionnaire at: App Store Connect > App > App Privacy

            # Use these commands as reference when filling out the form:
            asc privacy-types                  # All data types grouped by category
            asc privacy-purposes               # All purposes with descriptions
            asc privacy-labels                 # Instructions for web UI

          \e[1mUSER MANAGEMENT:\e[0m
            # View team:
            asc users                          # List all team members
            asc invitations                    # Pending invitations

            # Invite users:
            asc invite-user jane@example.com Jane Doe DEVELOPER
            asc invite-user john@example.com John Smith APP_MANAGER MARKETING

            # Manage users:
            asc remove-user user_id
            asc cancel-invitation invitation_id

          \e[1mUSE IN RUBY CODE:\e[0m
            require "app_store_connect"

            # Configure (optional if using env vars)
            AppStoreConnect.configure do |config|
              config.app_id = "123456789"
              config.bundle_id = "com.example.app"
            end

            client = AppStoreConnect::Client.new
            client.app_status
            client.review_submissions
            client.subscriptions
            client.in_app_purchases
            client.customer_reviews
            client.update_in_app_purchase(iap_id: "123", review_note: "Note for reviewer")
            client.create_customer_review_response(review_id: "456", response_body: "Thanks!")

        HELP
      end
    end
  end
end
