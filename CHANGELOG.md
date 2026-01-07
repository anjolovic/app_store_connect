# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2025-01-06

### Major Expansion Release

This release significantly expands the gem's capabilities, transforming it from a basic status checker into a comprehensive App Store Connect management tool.

### Added

#### In-App Purchase Management
- `in_app_purchase` - Get single IAP details
- `in_app_purchase_localizations` - Get IAP localizations
- `update_in_app_purchase` - Update IAP metadata and review notes
- `create_in_app_purchase_localization` - Create IAP localization
- `update_in_app_purchase_localization` - Update IAP description
- `delete_in_app_purchase_localization` - Delete IAP localization
- `submit_in_app_purchase` - Submit IAP for review
- CLI: `iaps`, `iap-details`, `update-iap-note`, `update-iap-description`, `submit-iap`

#### Customer Reviews
- `customer_reviews` - List customer reviews
- `customer_review_response` - Get existing response
- `create_customer_review_response` - Respond to review
- `delete_customer_review_response` - Delete response
- CLI: `customer-reviews`, `respond-review`

#### Screenshot & Preview Management
- `iap_review_screenshot` - Get IAP review screenshot
- `upload_iap_review_screenshot` - Upload IAP screenshot
- `delete_iap_review_screenshot` - Delete IAP screenshot
- `app_screenshot_sets` - Get screenshot sets
- `app_screenshots` - Get screenshots in a set
- `create_app_screenshot_set` - Create screenshot set
- `upload_app_screenshot` - Upload app screenshot
- `delete_app_screenshot` - Delete screenshot
- `reorder_app_screenshots` - Reorder screenshots
- `app_preview_sets` - Get preview sets
- `app_previews` - Get previews in a set
- `create_app_preview_set` - Create preview set
- `upload_app_preview` - Upload app preview video
- `delete_app_preview` - Delete preview
- CLI: `screenshots`, `upload-iap-screenshot`, `delete-iap-screenshot`, `upload-screenshot`, `delete-screenshot`

#### Release Automation
- `create_app_store_version` - Create new app version
- `update_app_store_version` - Update version settings
- `release_version` - Release pending version
- `phased_release` - Get phased release status
- `create_phased_release` - Enable phased rollout
- `update_phased_release` - Pause/resume/complete rollout
- `delete_phased_release` - Disable phased release
- `pre_order` - Get pre-order info
- `create_pre_order` - Enable pre-orders
- `update_pre_order` - Update pre-order date
- `delete_pre_order` - Cancel pre-orders
- CLI: `create-version`, `release`, `phased-release`, `enable-phased-release`, `pause-release`, `resume-release`, `complete-release`, `pre-order`, `enable-pre-order`, `cancel-pre-order`

#### TestFlight Automation
- `beta_testers` - List beta testers
- `beta_tester` - Get single tester
- `create_beta_tester` - Add beta tester
- `delete_beta_tester` - Remove beta tester
- `add_tester_to_groups` - Add tester to groups
- `remove_tester_from_groups` - Remove tester from groups
- `beta_groups` - List beta groups
- `beta_group` - Get single group
- `create_beta_group` - Create beta group
- `update_beta_group` - Update group settings
- `delete_beta_group` - Delete beta group
- `beta_group_testers` - List testers in group
- `add_testers_to_group` - Add testers to group
- `remove_testers_from_group` - Remove testers from group
- `testflight_builds` - List TestFlight builds
- `beta_build_detail` - Get beta build details
- `update_beta_build_detail` - Update build settings
- `add_build_to_groups` - Distribute build to groups
- `remove_build_from_groups` - Remove build from groups
- `build_beta_groups` - Get groups for a build
- `beta_build_localizations` - Get What's New
- `create_beta_build_localization` - Add What's New
- `update_beta_build_localization` - Update What's New
- `submit_for_beta_review` - Submit for beta review
- `beta_app_review_submission` - Get beta review status
- CLI: `testers`, `tester-groups`, `add-tester`, `remove-tester`, `create-group`, `delete-group`, `group-testers`, `add-to-group`, `remove-from-group`, `testflight-builds`, `distribute-build`, `remove-build`, `beta-whats-new`, `update-beta-whats-new`, `submit-beta-review`, `beta-review-status`

#### App Administration
- `app_info` - Get app info (age rating, categories)
- `app_info_localizations` - Get app name, subtitle, privacy URL
- `update_app_info_localization` - Update app metadata
- `app_categories` - Get app's categories
- `available_categories` - List all categories
- `update_app_categories` - Update categories
- `age_rating_declaration` - Get age rating
- `update_age_rating_declaration` - Update age rating
- CLI: `app-info`, `age-rating`, `categories`, `update-app-name`, `update-subtitle`

#### Pricing & Availability
- `app_price_schedule` - Get pricing schedule
- `app_price_points` - Get price points
- `app_availability` - Get territory availability
- `territories` - List all territories
- `update_app_availability` - Update availability
- CLI: `availability`, `territories`, `pricing`

#### Sales & Finance Reports
- `sales_report` - Get sales reports (gzipped TSV)
- `finance_report` - Get finance reports (gzipped TSV)

#### User Management
- `users` - List team users
- `user` - Get single user
- `update_user` - Update user roles
- `delete_user` - Remove user from team
- `user_invitations` - List pending invitations
- `create_user_invitation` - Invite new user
- `delete_user_invitation` - Cancel invitation
- CLI: `users`, `invitations`, `invite-user`, `remove-user`, `cancel-invitation`

#### App Privacy
- `app_data_usages` - Get privacy declarations
- `app_data_usage_categories` - List data categories
- `app_data_usage_purposes` - List data purposes
- CLI: `privacy-labels`

### Changed
- Expanded CLI help with comprehensive examples
- Updated README with full API documentation

---

## [1.0.0] - 2025-01-06

### Added

- Initial release
- `AppStoreConnect::Client` for API interactions
- `asc` CLI tool with read and write commands
- Configuration via environment variables or `AppStoreConnect.configure`
- Support for:
  - App status and version management
  - Review submissions (submit, cancel, check status)
  - Subscription products and localizations
  - App store version localizations (description, what's new, keywords)
  - Review details (contact info, demo account, notes)
  - Build listing
