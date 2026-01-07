# Upgrade Guide: v1.0.0 to v1.1.0

This guide helps you upgrade from App Store Connect gem v1.0.0 to v1.1.0 and take advantage of all the new features.

## Quick Start

### 1. Update the Gem

```ruby
# Gemfile
gem "app_store_connect", "~> 1.1"
```

```bash
bundle update app_store_connect
```

### 2. No Code Changes Required

Version 1.1.0 is fully backward compatible. Your existing code will continue to work without any modifications.

### 3. Explore New Features

Run `asc help` to see all 60+ new CLI commands, or continue reading for detailed examples.

---

## New Feature Overview

| Category | New Methods | New CLI Commands |
|----------|-------------|------------------|
| In-App Purchases | 7 | 5 |
| Customer Reviews | 4 | 2 |
| Screenshots & Previews | 15 | 5 |
| Release Automation | 11 | 10 |
| TestFlight | 24 | 16 |
| App Administration | 8 | 5 |
| Pricing & Availability | 5 | 3 |
| Reports | 2 | 0 |
| User Management | 7 | 5 |
| App Privacy | 3 | 1 |

---

## Detailed Feature Guide

### In-App Purchase Management

Previously, you could only list IAPs. Now you can fully manage them:

```ruby
client = AppStoreConnect::Client.new

# List all IAPs (existing)
iaps = client.in_app_purchases

# NEW: Get detailed info for a specific IAP
iap = client.in_app_purchase(iap_id: "123456")
# => { id: "123456", name: "Premium Upgrade", state: "APPROVED", ... }

# NEW: Get localizations
locs = client.in_app_purchase_localizations(iap_id: "123456")
# => [{ id: "loc1", locale: "en-US", description: "...", name: "..." }, ...]

# NEW: Update IAP review notes (what Apple reviewers see)
client.update_in_app_purchase(
  iap_id: "123456",
  review_note: "This IAP unlocks all premium features. Test with demo account."
)

# NEW: Update user-facing description
client.update_in_app_purchase_localization(
  localization_id: "loc1",
  description: "Unlock all premium features including..."
)

# NEW: Submit IAP for review
client.submit_in_app_purchase(iap_id: "123456")
```

**CLI Commands:**
```bash
asc iap-details                                    # Show all IAPs with localizations
asc update-iap-note com.app.premium "Review note"  # Update review notes
asc update-iap-description loc123 "Description"    # Update description
asc submit-iap com.app.premium                     # Submit for review
```

---

### Customer Review Responses

Respond to App Store reviews directly:

```ruby
# List recent reviews
reviews = client.customer_reviews(limit: 20)
reviews.each do |review|
  puts "#{review[:rating]} stars: #{review[:title]}"
  puts "  #{review[:body]}"
  puts "  From: #{review[:reviewer_nickname]}"
end

# Respond to a review
client.create_customer_review_response(
  review_id: "review123",
  response_body: "Thank you for your feedback! We've addressed this in our latest update."
)

# Check existing response
existing = client.customer_review_response(review_id: "review123")

# Delete a response (to edit, delete and recreate)
client.delete_customer_review_response(response_id: "response456")
```

**CLI Commands:**
```bash
asc customer-reviews                               # List recent reviews
asc respond-review review123 "Thank you for..."    # Respond to review
```

---

### Screenshot & Preview Management

Upload and manage App Store assets:

```ruby
# Get screenshot sets for a version localization
version = client.app_store_versions.first
loc = client.app_store_version_localizations(version_id: version["id"]).first
sets = client.app_screenshot_sets(localization_id: loc[:id])

# Create a new screenshot set (if needed)
client.create_app_screenshot_set(
  localization_id: loc[:id],
  display_type: "APP_IPHONE_67"  # iPhone 6.7" display
)

# Upload a screenshot
client.upload_app_screenshot(
  screenshot_set_id: sets.first[:id],
  file_path: "/path/to/screenshot.png"
)

# Reorder screenshots
client.reorder_app_screenshots(
  screenshot_set_id: sets.first[:id],
  screenshot_ids: ["s3", "s1", "s2"]  # New order
)

# Delete a screenshot
client.delete_app_screenshot(screenshot_id: "s1")

# Upload app preview video
preview_set = client.create_app_preview_set(
  localization_id: loc[:id],
  preview_type: "APP_IPHONE_67"
)
client.upload_app_preview(
  preview_set_id: preview_set[:id],
  file_path: "/path/to/preview.mp4",
  mime_type: "video/mp4"
)
```

**Display Types:**
- `APP_IPHONE_67` - iPhone 6.7" (14 Pro Max, 15 Pro Max)
- `APP_IPHONE_65` - iPhone 6.5" (11 Pro Max, XS Max)
- `APP_IPHONE_61` - iPhone 6.1" (14, 15)
- `APP_IPHONE_55` - iPhone 5.5" (8 Plus, 7 Plus)
- `APP_IPAD_PRO_129` - iPad Pro 12.9"
- `APP_IPAD_PRO_11` - iPad Pro 11"

**CLI Commands:**
```bash
asc screenshots                                    # List current screenshots
asc upload-screenshot APP_IPHONE_67 en-US ~/pic.png
asc delete-screenshot screenshot123
```

---

### Release Automation

Automate your entire release workflow:

```ruby
# Create a new version
client.create_app_store_version(
  version_string: "2.0.0",
  platform: "IOS",
  release_type: "AFTER_APPROVAL"  # Auto-release when approved
)

# Or create with manual release
client.create_app_store_version(
  version_string: "2.0.0",
  platform: "IOS",
  release_type: "MANUAL"  # Hold for manual release
)

# Enable phased release (gradual 7-day rollout)
version = client.app_store_versions.first
client.create_phased_release(version_id: version["id"])

# Check rollout progress
# Day 1: 1%, Day 2: 2%, Day 3: 5%, Day 4: 10%, Day 5: 20%, Day 6: 50%, Day 7: 100%
phased = client.phased_release(version_id: version["id"])
puts "Day #{phased[:current_day_number]}: #{phased[:state]}"

# Pause if issues found
client.update_phased_release(phased_release_id: phased[:id], state: "PAUSED")

# Resume rollout
client.update_phased_release(phased_release_id: phased[:id], state: "ACTIVE")

# Release to everyone immediately
client.update_phased_release(phased_release_id: phased[:id], state: "COMPLETE")

# Manual release (for MANUAL release type)
client.release_version(version_id: version["id"])

# Pre-orders
client.create_pre_order(app_release_date: "2025-06-01")
client.update_pre_order(pre_order_id: "po123", app_release_date: "2025-07-01")
client.delete_pre_order(pre_order_id: "po123")
```

**CLI Commands:**
```bash
asc create-version 2.0.0                    # Create version (auto-release)
asc create-version 2.0.0 MANUAL             # Create with manual release

asc enable-phased-release                   # Enable gradual rollout
asc phased-release                          # Check rollout status
asc pause-release                           # Pause if issues
asc resume-release                          # Resume rollout
asc complete-release                        # Release to all users

asc release                                 # Manual release

asc enable-pre-order 2025-06-01             # Enable pre-orders
asc pre-order                               # Check status
asc cancel-pre-order                        # Cancel pre-orders
```

---

### TestFlight Automation

Complete TestFlight management:

```ruby
# === Beta Testers ===

# List all testers
testers = client.beta_testers
testers.each do |t|
  puts "#{t[:email]}: #{t[:state]}"
end

# Add a tester
client.create_beta_tester(
  email: "tester@example.com",
  first_name: "Jane",
  last_name: "Doe",
  group_ids: ["group1"]  # Optional: add to groups
)

# Remove a tester
client.delete_beta_tester(tester_id: "t123")

# === Beta Groups ===

# List groups
groups = client.beta_groups
groups.each do |g|
  puts "#{g[:name]}: #{g[:is_internal] ? 'Internal' : 'External'}"
end

# Create a group
client.create_beta_group(
  name: "External Testers",
  public_link_enabled: true,
  public_link_limit: 1000,
  public_link_limit_enabled: true
)

# Add testers to group
client.add_testers_to_group(
  group_id: "g123",
  tester_ids: ["t1", "t2", "t3"]
)

# === Build Distribution ===

# List builds
builds = client.testflight_builds
builds.each do |b|
  puts "Build #{b[:version]}: #{b[:processing_state]}"
end

# Distribute to groups
client.add_build_to_groups(
  build_id: "b123",
  group_ids: ["group1", "group2"]
)

# Set What's New for TestFlight
client.create_beta_build_localization(
  build_id: "b123",
  locale: "en-US",
  whats_new: "Bug fixes and new features for testing"
)

# Submit for external beta review
client.submit_for_beta_review(build_id: "b123")

# Check review status
status = client.beta_app_review_submission(build_id: "b123")
puts "Beta review: #{status[:beta_review_state]}"
```

**CLI Commands:**
```bash
# Testers
asc testers                                        # List testers
asc add-tester test@example.com Jane Doe           # Add tester
asc add-tester test@example.com Jane Doe group1    # Add to group
asc remove-tester tester123                        # Remove tester

# Groups
asc tester-groups                                  # List groups
asc create-group "Beta Testers"                    # Create group
asc create-group "Public Beta" --public --limit 500
asc delete-group group123
asc group-testers group123                         # List testers in group
asc add-to-group group123 tester1 tester2          # Add to group
asc remove-from-group group123 tester1             # Remove from group

# Builds
asc testflight-builds                              # List builds
asc distribute-build build123 group1 group2        # Distribute
asc remove-build build123 group1                   # Remove from group

# What's New
asc beta-whats-new build123                        # Show What's New
asc update-beta-whats-new build123 "Bug fixes"     # Update

# Beta Review
asc submit-beta-review build123                    # Submit for review
asc beta-review-status build123                    # Check status
```

---

### App Administration

Manage app metadata, categories, and age ratings:

```ruby
# Get app info
infos = client.app_info
info = infos.first

# Get localizations (name, subtitle, privacy URL)
locs = client.app_info_localizations(app_info_id: info[:id])
locs.each do |loc|
  puts "#{loc[:locale]}: #{loc[:name]} - #{loc[:subtitle]}"
end

# Update app name or subtitle
client.update_app_info_localization(
  localization_id: locs.first[:id],
  name: "My Awesome App",
  subtitle: "The best app ever",
  privacy_policy_url: "https://example.com/privacy"
)

# Get age rating
rating = client.age_rating_declaration(app_info_id: info[:id])
puts "Violence: #{rating[:violence_cartoon_or_fantasy]}"
puts "17+: #{rating[:seventeen_plus]}"

# Update age rating
client.update_age_rating_declaration(
  declaration_id: rating[:id],
  violence_cartoon_or_fantasy: "INFREQUENT_OR_MILD",
  gambling: "NONE",
  seventeen_plus: false
)

# List available categories
categories = client.available_categories(platform: "IOS")

# Update app categories
client.update_app_categories(
  app_info_id: info[:id],
  primary_category_id: "GAMES_ACTION",
  secondary_category_id: "ENTERTAINMENT"
)
```

**CLI Commands:**
```bash
asc app-info                              # Show app info
asc age-rating                            # Show age ratings
asc categories                            # List categories
asc update-app-name "My New App Name"     # Update name
asc update-subtitle "New Subtitle"        # Update subtitle
```

---

### Pricing & Availability

View and manage where your app is available:

```ruby
# Get app availability
availability = client.app_availability
puts "Available in #{availability[:territories].length} territories"
puts "Auto-add new territories: #{availability[:available_in_new_territories]}"

# List all territories
territories = client.territories
territories.each do |t|
  puts "#{t[:id]}: #{t[:currency]}"
end

# Get price schedule
schedule = client.app_price_schedule
puts "Base territory: #{schedule[:base_territory]}"

# Get price points for a territory
points = client.app_price_points(territory: "USA", limit: 20)
points.each do |p|
  puts "#{p[:id]}: $#{p[:customer_price]} (proceeds: $#{p[:proceeds]})"
end

# Update availability settings
client.update_app_availability(
  availability_id: availability[:id],
  available_in_new_territories: true
)
```

**CLI Commands:**
```bash
asc availability                          # Show where app is available
asc territories                           # List all territories
asc pricing                               # Show price schedule
```

---

### Sales & Finance Reports

Download sales and finance reports:

```ruby
# Get daily sales report
# Note: Returns gzipped TSV data
report = client.sales_report(
  vendor_number: "12345678",     # Your vendor number
  frequency: "DAILY",            # DAILY, WEEKLY, MONTHLY, YEARLY
  report_type: "SALES",          # SALES, PRE_ORDER, SUBSCRIPTION, SUBSCRIBER
  report_sub_type: "SUMMARY",    # SUMMARY, DETAILED, OPT_IN
  report_date: "2025-01-01"      # Optional: specific date
)

# Save to file and decompress
File.binwrite("sales_report.tsv.gz", report)
`gunzip sales_report.tsv.gz`

# Get finance report
finance = client.finance_report(
  vendor_number: "12345678",
  region_code: "US",             # US, EU, JP, etc.
  report_type: "FINANCIAL",
  report_date: "2025-01"         # YYYY-MM format
)
```

---

### User Management

Manage team members and invitations:

```ruby
# List all team users
users = client.users
users.each do |u|
  puts "#{u[:first_name]} #{u[:last_name]} (#{u[:email]})"
  puts "  Roles: #{u[:roles].join(', ')}"
end

# Get specific user
user = client.user(user_id: "u123")

# Update user roles
client.update_user(
  user_id: "u123",
  roles: ["APP_MANAGER", "MARKETING"],
  all_apps_visible: false
)

# Remove user from team
client.delete_user(user_id: "u123")

# List pending invitations
invitations = client.user_invitations
invitations.each do |i|
  puts "#{i[:email]}: expires #{i[:expiration_date]}"
end

# Invite a new user
client.create_user_invitation(
  email: "newuser@example.com",
  first_name: "Jane",
  last_name: "Doe",
  roles: ["DEVELOPER"],
  all_apps_visible: true
)

# Invite with limited app access
client.create_user_invitation(
  email: "contractor@example.com",
  first_name: "John",
  last_name: "Smith",
  roles: ["DEVELOPER"],
  all_apps_visible: false,
  visible_app_ids: ["app123", "app456"]
)

# Cancel invitation
client.delete_user_invitation(invitation_id: "inv123")
```

**Available Roles:**
- `ADMIN` - Full access
- `FINANCE` - Financial reports and agreements
- `ACCOUNT_HOLDER` - Account owner
- `SALES` - Sales reports
- `MARKETING` - Marketing tools
- `APP_MANAGER` - Manage apps and metadata
- `DEVELOPER` - Development access
- `ACCESS_TO_REPORTS` - View reports only
- `CUSTOMER_SUPPORT` - Customer support tools
- `CREATE_APPS` - Create new apps

**CLI Commands:**
```bash
asc users                                          # List users
asc invitations                                    # List invitations
asc invite-user jane@example.com Jane Doe DEVELOPER
asc invite-user john@example.com John Smith APP_MANAGER MARKETING
asc remove-user user123                            # Remove from team
asc cancel-invitation inv123                       # Cancel invitation
```

---

### App Privacy

View privacy declarations:

```ruby
# Get privacy data usage declarations
usages = client.app_data_usages
usages.each do |u|
  puts "#{u[:category]}: #{u[:purposes].join(', ')}"
  puts "  Protection: #{u[:data_protection]}"
end

# Reference: available categories
categories = client.app_data_usage_categories
# => [{ id: "EMAIL_ADDRESS", name: "Email Address" }, ...]

# Reference: available purposes
purposes = client.app_data_usage_purposes
# => [{ id: "ANALYTICS", name: "Analytics" }, ...]
```

**CLI Commands:**
```bash
asc privacy-labels                        # Show privacy declarations
```

---

## Common Workflows

### Responding to Apple Review Rejection

```bash
# 1. Check what Apple is asking for
asc review-info

# 2. Update reviewer notes if they need demo account
asc update-review-notes "Demo account: test@example.com / Password123"

# 3. Update IAP notes if they rejected an IAP
asc update-iap-note com.app.premium "This unlocks premium features. Use demo account."

# 4. Resubmit
asc submit
```

### Preparing a New Release

```bash
# 1. Create new version
asc create-version 2.0.0

# 2. Update What's New
asc update-whats-new "New features and bug fixes"

# 3. Upload new screenshots if needed
asc upload-screenshot APP_IPHONE_67 en-US ~/Desktop/screenshot.png

# 4. Enable phased release for safety
asc enable-phased-release

# 5. Submit for review
asc submit
```

### Managing TestFlight Beta

```bash
# 1. Check latest builds
asc testflight-builds

# 2. Add What's New for testers
asc update-beta-whats-new BUILD_ID "Testing new feature X"

# 3. Distribute to external group
asc distribute-build BUILD_ID external_group_id

# 4. Submit for beta review (external testers)
asc submit-beta-review BUILD_ID

# 5. Check review status
asc beta-review-status BUILD_ID
```

### Inviting a New Team Member

```bash
# 1. Send invitation
asc invite-user developer@company.com Jane Doe DEVELOPER

# 2. Check pending invitations
asc invitations

# 3. Cancel if needed
asc cancel-invitation INVITATION_ID
```

---

## Need Help?

- Run `asc help` for full command reference
- Check the [README](README.md) for API documentation
- Report issues at https://github.com/anjolovic/app_store_connect
