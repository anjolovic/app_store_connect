# App Store Connect

A Ruby library and command-line tool for interacting with Apple's App Store Connect API.

## Features

- Check app status, versions, and review submissions
- List and manage subscription products
- View and update app metadata (description, what's new, keywords)
- Update reviewer notes and demo account info
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

# Check submission readiness
asc ready

# List all apps in your account
asc apps

# List recent builds
asc builds
```

### Responding to Apple Review Requests

```bash
# Update notes for reviewer
asc update-review-notes "Please use demo account: test@example.com / Password123!"

# Update "What's New" text
asc update-whats-new "Bug fixes and performance improvements"

# Update subscription description
asc update-sub-description com.example.app.plan.starter.monthly "Access basic features"

# Submit for review
asc submit

# Cancel pending review
asc cancel-review
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
| `subscription_prices` | Get subscription prices |
| `builds` | List recent builds |
| `app_store_version_localizations` | Get version localizations |
| `app_store_review_detail` | Get review contact info |
| `beta_app_review_detail` | Get TestFlight review info |
| `in_app_purchases` | List in-app purchases |

### Write Methods

| Method | Description |
|--------|-------------|
| `update_subscription` | Update subscription metadata |
| `update_subscription_localization` | Update subscription description |
| `create_subscription_localization` | Create new localization |
| `update_app_store_version_localization` | Update version metadata |
| `update_app_store_review_detail` | Update reviewer notes |
| `update_beta_app_review_detail` | Update TestFlight notes |
| `create_review_submission` | Submit for review |
| `cancel_review_submission` | Cancel pending review |

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
