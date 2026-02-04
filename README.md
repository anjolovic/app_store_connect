# App Store Connect

A Ruby library and command-line tool for interacting with Apple's App Store Connect API.

## Features

- Check app status, versions, and review submissions
- List and manage subscription products
- List and manage in-app purchases (update metadata, descriptions, submit for review)
- View and update app metadata (description, what's new, keywords)
- Update reviewer notes and demo account info
- Respond to customer reviews
- Submit apps for review and cancel pending submissions
- Works with any Ruby project (no Rails dependency)

## Installation

Add this line to your application's Gemfile:

```ruby
gem "app_store_connect"
```

Or install it yourself:

```bash
gem install app_store_connect
```

## Setup

### 1. Generate an App Store Connect API Key

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Navigate to **Users and Access > Integrations > App Store Connect API**
3. Click **Generate API Key**
4. Select role: **Admin** or **App Manager**
5. Download the `.p8` file (you can only download once!)
6. Note the **Key ID** shown on the page

### 2. Store the Key Securely

```bash
mkdir -p ~/.config/app_store_connect/keys
mv AuthKey_XXXX.p8 ~/.config/app_store_connect/keys/
chmod 600 ~/.config/app_store_connect/keys/AuthKey_XXXX.p8
```

### 3. Configure Environment Variables

```bash
export APP_STORE_CONNECT_KEY_ID=YOUR_KEY_ID
export APP_STORE_CONNECT_ISSUER_ID=YOUR_ISSUER_ID
export APP_STORE_CONNECT_PRIVATE_KEY_PATH=/path/to/AuthKey_XXXX.p8
export APP_STORE_CONNECT_APP_ID=YOUR_APP_ID
export APP_STORE_CONNECT_BUNDLE_ID=com.example.app
```

Optional SSL settings (use only if your environment has TLS/CRL issues):

```bash
# Disable CRL verification (default: true)
export APP_STORE_CONNECT_SKIP_CRL_VERIFICATION=true

# Disable SSL verification entirely (default: true; set false only if needed)
export APP_STORE_CONNECT_VERIFY_SSL=false

# Use curl-based HTTP client (default: false)
export APP_STORE_CONNECT_USE_CURL=true

# Retry multipart asset uploads (screenshots/images) on transient failures (default: 3)
export APP_STORE_CONNECT_UPLOAD_RETRIES=3

# Base sleep seconds between retries (default: 1.0)
export APP_STORE_CONNECT_UPLOAD_RETRY_SLEEP=1.0
```

Or in a Rails initializer:

```ruby
# config/initializers/app_store_connect.rb
AppStoreConnect.configure do |config|
  config.key_id = ENV["APP_STORE_CONNECT_KEY_ID"]
  config.issuer_id = ENV["APP_STORE_CONNECT_ISSUER_ID"]
  config.private_key_path = ENV["APP_STORE_CONNECT_PRIVATE_KEY_PATH"]
  config.app_id = "123456789"
  config.bundle_id = "com.example.app"
end
```

## Rails Integration

For Rails projects using `dotenv-rails`, the CLI will automatically load your `.env` file.

### 1. Add to Gemfile

```ruby
gem "app_store_connect", path: "~/Web/RubyGems/app_store_connect"
```

### 2. Add environment variables to `.env`

```bash
APP_STORE_CONNECT_KEY_ID=YOUR_KEY_ID
APP_STORE_CONNECT_ISSUER_ID=YOUR_ISSUER_ID
APP_STORE_CONNECT_PRIVATE_KEY_PATH=AuthKey_XXXX.p8
APP_STORE_CONNECT_APP_ID=YOUR_APP_ID
APP_STORE_CONNECT_BUNDLE_ID=com.example.app
```

### 3. Run bundle install

```bash
bundle install
```

### 4. Use the CLI

```bash
bundle exec asc status
```

## Command Line Usage

```bash
# Check overall app status
asc status

# Check review submission status
asc review

# View subscription products
asc subs

# View detailed subscription info with localizations
asc sub-details

# Create a subscription product
asc create-sub com.example.app.plan.monthly "Monthly Plan" 1m --group "Main Plans" --create-group

# Create with price + intro offer (example)
asc create-sub com.example.app.plan.monthly "Monthly Plan" 1m \
  --group "Main Plans" --create-group \
  --price-point PRICE_POINT_ID --price-start-date 2026-03-01 \
  --intro-offer FREE_TRIAL --intro-duration 1w --intro-price-point INTRO_PRICE_POINT_ID

# Fix missing metadata on an existing subscription
asc fix-sub-metadata com.example.app.plan.monthly \
  --display-name "Monthly Plan" \
  --description "Access premium features" \
  --price-point PRICE_POINT_ID

# View in-app purchases
asc iaps

# View detailed IAP info with localizations
asc iap-details

# View customer reviews
asc customer-reviews

# Check submission readiness
asc ready

# List all apps in your account
asc apps

# List recent builds
asc builds
```

### Create Subscription Options

```bash
# Dry run (no changes)
asc create-sub com.example.app.plan.monthly "Monthly Plan" 1m --group "Main Plans" --create-group --dry-run

# Skip confirmation + JSON output
asc create-sub com.example.app.plan.monthly "Monthly Plan" 1m --group-id 12345 --yes --json

# Add localizations
asc create-sub com.example.app.plan.monthly "Monthly Plan" 1m \
  --group-id 12345 \
  --add-localization "en-US:Monthly Plan:Access premium features" \
  --add-localization "fr-FR:Forfait mensuel:Acces aux fonctionnalites premium"

# Localizations from file (JSON or YAML)
asc create-sub com.example.app.plan.monthly "Monthly Plan" 1m \
  --group-id 12345 \
  --localizations-file ./config/subscription_localizations.yml
```

### Subscription Management

```bash
# Availability (territories)
asc sub-availability com.example.app.plan.monthly
asc set-sub-availability com.example.app.plan.monthly USA CAN GBR --available-in-new-territories true

# Price points and schedule
asc sub-price-points com.example.app.plan.monthly USA --all
# Note: --all uses a large limit (2000) because cursor pagination is unreliable for this endpoint.
asc sub-price-points com.example.app.plan.monthly USA --limit 2000
asc sub-price-points com.example.app.plan.monthly USA --search-price 599
asc sub-prices com.example.app.plan.monthly
asc add-sub-price com.example.app.plan.monthly PRICE_POINT_ID --start-date 2026-03-01

# Subscription image (1024x1024)
asc sub-image com.example.app.plan.monthly
asc upload-sub-image com.example.app.plan.monthly ./subscription.png
asc delete-sub-image com.example.app.plan.monthly

# Review screenshot
asc sub-review-screenshot com.example.app.plan.monthly
asc upload-sub-review-screenshot com.example.app.plan.monthly ./review.png
asc upload-sub-review-screenshot com.example.app.plan.monthly --capture --output ./subscription-review.png
asc delete-sub-review-screenshot com.example.app.plan.monthly

# Ensure assets for all subscriptions (review screenshot + 1024x1024 image)
asc sub-ensure-assets \
  --review-screenshot ./paywall.png \
  --image-file ./subscription-logo-1024.png \
  --only-missing \
  --yes \
  --wait

# Localizations
asc sub-localizations com.example.app.plan.monthly
asc update-sub-localization com.example.app.plan.monthly en-US --name "Monthly Plan" --description "Access premium features"

# Introductory offers
asc sub-intro-offers com.example.app.plan.monthly
asc delete-sub-intro-offer OFFER_ID

# Tax category
asc set-sub-tax-category com.example.app.plan.monthly TAX_CATEGORY_ID
asc tax-categories
Note: if `tax-categories` returns Not found, set `APP_STORE_CONNECT_APP_ID` to enable the app-scoped fallback.
```

### Responding to Apple Review Requests

```bash
# Update notes for reviewer
asc update-review-notes "Please use demo account: test@example.com / Password123!"

# Update "What's New" text
asc update-whats-new "Bug fixes and performance improvements"

# Update subscription description
asc update-sub-description com.example.app.plan.starter.monthly "Access basic features"

# Update IAP review notes (for Apple reviewers)
asc update-iap-note com.example.app.coins.100 "Unlocks 100 coins for gameplay"

# Update IAP description (shown to users)
asc update-iap-description com.example.app.coins.100 "Get 100 coins to use in-game"

# Submit IAP for review
asc submit-iap com.example.app.coins.100

# Respond to customer reviews
asc respond-review abc123 "Thank you for your feedback!"

# Submit for review
asc submit

# Cancel pending review
asc cancel-review
```

### Screenshot Management

```bash
# View current screenshots
asc screenshots

# Upload IAP review screenshot
asc upload-iap-screenshot com.example.app.coins.100 ~/Desktop/iap-screenshot.png

# Delete IAP review screenshot
asc delete-iap-screenshot com.example.app.coins.100

# Upload app screenshot (for iPhone 6.7")
asc upload-screenshot APP_IPHONE_67 en-US ~/Desktop/screenshot.png

# Delete app screenshot
asc delete-screenshot abc123
```

### Release Automation

```bash
# Create a new version
asc create-version 2.0.0
asc create-version 2.0.0 MANUAL    # Hold for manual release after approval

# Enable phased rollout (gradual 7-day release)
asc enable-phased-release

# Control phased release
asc phased-release                 # Check status
asc pause-release                  # Pause if issues found
asc resume-release                 # Resume rollout
asc complete-release               # Release to all users now

# Manual release (for MANUAL release type)
asc release

# Pre-orders
asc enable-pre-order 2025-06-01
asc pre-order                      # Check status
asc cancel-pre-order
```

### TestFlight Automation

```bash
# List beta testers and groups
asc testers
asc tester-groups

# Add/remove testers
asc add-tester test@example.com John Doe
asc add-tester test@example.com John Doe group_id_1 group_id_2
asc remove-tester tester_id

# Manage beta groups
asc create-group "External Testers"
asc create-group "Public Beta" --public --limit 1000
asc delete-group group_id
asc group-testers group_id

# Add/remove testers from groups
asc add-to-group group_id tester1 tester2
asc remove-from-group group_id tester1

# Distribute builds
asc testflight-builds
asc distribute-build build_id group_id
asc remove-build build_id group_id

# Beta What's New text
asc beta-whats-new build_id
asc update-beta-whats-new build_id "Bug fixes and improvements"

# Submit for external beta review
asc submit-beta-review build_id
asc beta-review-status build_id
```

### App Administration

```bash
# View app info
asc app-info                         # App name, subtitle, localizations
asc age-rating                       # Age rating declaration
asc categories                       # Available categories

# Update app metadata
asc update-app-name "My App"
asc update-subtitle "Best app ever"

# Availability and pricing
asc availability                     # Where app is available
asc territories                      # All territories
asc pricing                          # Price schedule and points

# Privacy labels
asc privacy-labels                   # Data usage declarations
```

### User Management

```bash
# View team
asc users                            # List team users
asc invitations                      # Pending invitations

# Invite users
asc invite-user jane@example.com Jane Doe DEVELOPER
asc invite-user john@example.com John Smith APP_MANAGER MARKETING

# Manage users
asc remove-user user_id
asc cancel-invitation invitation_id
```

### Show Help

```bash
asc help
```

## Ruby API Usage

```ruby
require "app_store_connect"

# Configure (optional if using environment variables)
AppStoreConnect.configure do |config|
  config.app_id = "123456789"
  config.bundle_id = "com.example.app"
end

# Create a client
client = AppStoreConnect::Client.new

# Get app status summary
status = client.app_status
puts status[:app][:name]
puts status[:versions].map { |v| "#{v[:version]}: #{v[:state]}" }

# Check review submissions
reviews = client.review_submissions
reviews.each do |r|
  puts "#{r.dig('attributes', 'state')} - #{r.dig('attributes', 'platform')}"
end

# List subscriptions
subs = client.subscriptions
subs.each do |s|
  puts "#{s.dig('attributes', 'name')}: #{s.dig('attributes', 'state')}"
end

# Get subscription localizations
locs = client.subscription_localizations(subscription_id: "abc123")
locs.each do |loc|
  puts "#{loc[:locale]}: #{loc[:description]}"
end

# Update subscription description
client.update_subscription_localization(
  localization_id: "xyz789",
  description: "New subscription description"
)

# Get app store version localizations
versions = client.app_store_versions
version_id = versions.first["id"]
version_locs = client.app_store_version_localizations(version_id: version_id)

# Update "What's New" text
client.update_app_store_version_localization(
  localization_id: version_locs.first[:id],
  whats_new: "Bug fixes and improvements"
)

# Check submission readiness
result = client.submission_readiness
if result[:ready]
  puts "Ready for submission!"
else
  puts "Issues found: #{result[:issues].join(', ')}"
end

# Submit for review
client.create_review_submission(platform: "IOS")

# Cancel pending review
client.cancel_review_submission(submission_id: "submission_id")

# List in-app purchases
iaps = client.in_app_purchases
iaps.each do |iap|
  puts "#{iap[:name]}: #{iap[:state]} (#{iap[:type]})"
end

# Update IAP review notes
client.update_in_app_purchase(iap_id: "123", review_note: "This unlocks premium features")

# Get IAP localizations
locs = client.in_app_purchase_localizations(iap_id: "123")

# Update IAP description
client.update_in_app_purchase_localization(
  localization_id: "456",
  description: "Get access to all premium features"
)

# Submit IAP for review
client.submit_in_app_purchase(iap_id: "123")

# List customer reviews
reviews = client.customer_reviews(limit: 20)
reviews.each do |review|
  puts "#{review[:rating]} stars: #{review[:title]}"
end

# Respond to a customer review
client.create_customer_review_response(
  review_id: "abc123",
  response_body: "Thank you for your feedback!"
)
```

## Available Methods

### Read Methods

| Method | Description |
|--------|-------------|
| `app_status` | Full app status summary |
| `submission_readiness` | Check if ready for submission |
| `apps` | List all apps |
| `app_store_versions` | List app versions |
| `review_submissions` | List review submissions |
| `subscriptions` | List subscription products |
| `subscription_localizations` | Get subscription localizations |
| `subscription_availability` | Get subscription availability |
| `subscription_images` | Get subscription images |
| `subscription_review_screenshot` | Get subscription review screenshot |
| `subscription_introductory_offers` | List subscription intro offers |
| `tax_categories` | List available tax categories |
| `subscription_prices` | Get subscription prices |
| `builds` | List recent builds |
| `app_store_version_localizations` | Get version localizations |
| `app_store_review_detail` | Get review contact info |
| `beta_app_review_detail` | Get TestFlight review info |
| `in_app_purchases` | List in-app purchases |
| `in_app_purchase` | Get single IAP details |
| `in_app_purchase_localizations` | Get IAP localizations |
| `customer_reviews` | List customer reviews |
| `customer_review_response` | Get response to a review |
| `iap_review_screenshot` | Get IAP review screenshot |
| `app_screenshot_sets` | Get screenshot sets for a localization |
| `app_screenshots` | Get screenshots in a set |
| `app_preview_sets` | Get preview sets for a localization |
| `app_previews` | Get previews in a set |
| `phased_release` | Get phased release status |
| `pre_order` | Get pre-order info |
| `beta_testers` | List beta testers |
| `beta_tester` | Get single beta tester |
| `beta_groups` | List beta groups |
| `beta_group` | Get single beta group |
| `beta_group_testers` | List testers in a group |
| `testflight_builds` | List TestFlight builds |
| `beta_build_detail` | Get beta build details |
| `build_beta_groups` | Get groups for a build |
| `beta_build_localizations` | Get What's New for build |
| `beta_app_review_submission` | Get beta review status |
| `app_info` | Get app info (age rating, categories) |
| `app_info_localizations` | Get app name, subtitle, privacy URL |
| `app_categories` | Get app's primary/secondary categories |
| `available_categories` | List all available categories |
| `age_rating_declaration` | Get age rating declaration |
| `app_price_schedule` | Get pricing schedule |
| `app_price_points` | Get available price points |
| `app_availability` | Get territory availability |
| `territories` | List all territories |
| `users` | List team users |
| `user` | Get single user |
| `user_invitations` | List pending invitations |
| `app_data_usages` | Get privacy data declarations |
| `sales_report` | Get sales report (gzipped) |
| `finance_report` | Get finance report (gzipped) |

### Write Methods

| Method | Description |
|--------|-------------|
| `update_subscription` | Update subscription metadata |
| `update_subscription_localization` | Update subscription description |
| `create_subscription_localization` | Create new subscription localization |
| `create_subscription` | Create a subscription product |
| `create_subscription_group` | Create a subscription group |
| `create_subscription_price` | Set a subscription price |
| `create_subscription_introductory_offer` | Create an introductory offer |
| `create_subscription_availability` | Create subscription availability |
| `update_subscription_availability` | Update subscription availability |
| `upload_subscription_image` | Upload subscription image |
| `delete_subscription_image` | Delete subscription image |
| `upload_subscription_review_screenshot` | Upload subscription review screenshot |
| `delete_subscription_review_screenshot` | Delete subscription review screenshot |
| `update_subscription_tax_category` | Update subscription tax category |
| `delete_subscription_introductory_offer` | Delete subscription intro offer |
| `update_app_store_version_localization` | Update version metadata |
| `update_app_store_review_detail` | Update reviewer notes |
| `update_beta_app_review_detail` | Update TestFlight notes |
| `create_review_submission` | Submit for review |
| `cancel_review_submission` | Cancel pending review |
| `update_in_app_purchase` | Update IAP metadata/review notes |
| `create_in_app_purchase_localization` | Create IAP localization |
| `update_in_app_purchase_localization` | Update IAP description |
| `delete_in_app_purchase_localization` | Delete IAP localization |
| `submit_in_app_purchase` | Submit IAP for review |
| `create_customer_review_response` | Respond to customer review |
| `delete_customer_review_response` | Delete review response |
| `upload_iap_review_screenshot` | Upload IAP review screenshot |
| `delete_iap_review_screenshot` | Delete IAP review screenshot |
| `create_app_screenshot_set` | Create screenshot set |
| `upload_app_screenshot` | Upload app screenshot |
| `delete_app_screenshot` | Delete app screenshot |
| `reorder_app_screenshots` | Reorder screenshots in a set |
| `create_app_preview_set` | Create app preview set |
| `upload_app_preview` | Upload app preview video |
| `delete_app_preview` | Delete app preview |
| `create_app_store_version` | Create new app version |
| `update_app_store_version` | Update version settings |
| `release_version` | Release pending version |
| `create_phased_release` | Enable phased rollout |
| `update_phased_release` | Pause/resume/complete rollout |
| `delete_phased_release` | Disable phased release |
| `create_pre_order` | Enable pre-orders |
| `update_pre_order` | Update pre-order date |
| `delete_pre_order` | Cancel pre-orders |
| `create_beta_tester` | Add a beta tester |
| `delete_beta_tester` | Remove a beta tester |
| `add_tester_to_groups` | Add tester to groups |
| `remove_tester_from_groups` | Remove tester from groups |
| `create_beta_group` | Create a beta group |
| `update_beta_group` | Update beta group settings |
| `delete_beta_group` | Delete a beta group |
| `add_testers_to_group` | Add testers to a group |
| `remove_testers_from_group` | Remove testers from group |
| `add_build_to_groups` | Distribute build to groups |
| `remove_build_from_groups` | Remove build from groups |
| `update_beta_build_detail` | Update beta build settings |
| `create_beta_build_localization` | Add What's New text |
| `update_beta_build_localization` | Update What's New text |
| `submit_for_beta_review` | Submit for beta review |
| `update_app_info_localization` | Update app name/subtitle/privacy URL |
| `update_app_categories` | Update app categories |
| `update_age_rating_declaration` | Update age rating |
| `update_app_availability` | Update territory availability |
| `update_user` | Update user roles |
| `delete_user` | Remove user from team |
| `create_user_invitation` | Invite new user |
| `delete_user_invitation` | Cancel invitation |

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests.

```bash
bundle install
bundle exec rspec
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/anjolovic/app_store_connect.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
