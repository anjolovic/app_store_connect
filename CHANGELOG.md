# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
