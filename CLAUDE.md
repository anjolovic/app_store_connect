# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Run a single test file
bundle exec rspec spec/path/to/file_spec.rb

# Run linter
bundle exec rubocop

# Run linter with auto-fix
bundle exec rubocop -a

# Run all checks (tests + linting)
bundle exec rake

# Run the CLI locally
bundle exec exe/asc status
```

## Architecture

This gem provides both a Ruby API client and CLI (`asc`) for Apple's App Store Connect API.

### Core Components

- **`lib/app_store_connect.rb`** - Module entry point with global configuration via `AppStoreConnect.configure` block
- **`lib/app_store_connect/client.rb`** - API client that wraps all App Store Connect REST endpoints. Uses JWT authentication with ES256 signing. Makes HTTP requests via `curl` to avoid Ruby SSL CRL verification issues.
- **`lib/app_store_connect/cli.rb`** - Command-line interface that maps commands like `asc status`, `asc review`, `asc subs` to client methods
- **`lib/app_store_connect/configuration.rb`** - Configuration object that reads from environment variables (`APP_STORE_CONNECT_*`)
- **`exe/asc`** - CLI entrypoint that auto-loads dotenv if available

### API Pattern

The Client class follows a consistent pattern:
- Read methods return parsed/simplified Ruby hashes (not raw API responses)
- Write methods (`update_*`, `create_*`, `delete_*`) take keyword arguments and return API responses
- All methods use `@app_id` from configuration by default, but accept `target_app_id:` override

### Supported Resources

**App Management:** apps, versions, version localizations, review submissions, review details
**Subscriptions:** subscription groups, subscriptions, subscription localizations, prices
**In-App Purchases:** IAPs, IAP localizations, IAP submissions
**Customer Reviews:** reviews, review responses
**Builds:** build listing and metadata

### Required Environment Variables

- `APP_STORE_CONNECT_KEY_ID` - API Key ID
- `APP_STORE_CONNECT_ISSUER_ID` - Issuer ID (same for all keys in a team)
- `APP_STORE_CONNECT_PRIVATE_KEY_PATH` - Path to .p8 private key file
- `APP_STORE_CONNECT_APP_ID` - Target app's Apple ID
- `APP_STORE_CONNECT_BUNDLE_ID` - Target app's bundle identifier
