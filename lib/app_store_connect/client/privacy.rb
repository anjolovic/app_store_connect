# frozen_string_literal: true

module AppStoreConnect
  class Client
    # App privacy reference data
    # NOTE: Apple's API does NOT support creating/reading/deleting privacy declarations.
    # The App Privacy questionnaire must be completed via App Store Connect web UI.
    # These methods provide reference data for documentation purposes.
    module Privacy
      # Reference: All available privacy data types (categories)
      # Use these when completing the App Privacy questionnaire in App Store Connect
      def privacy_data_types
        [
          # Contact Info
          { id: 'NAME', name: 'Name', category: 'Contact Info' },
          { id: 'EMAIL_ADDRESS', name: 'Email Address', category: 'Contact Info' },
          { id: 'PHONE_NUMBER', name: 'Phone Number', category: 'Contact Info' },
          { id: 'PHYSICAL_ADDRESS', name: 'Physical Address', category: 'Contact Info' },
          { id: 'OTHER_USER_CONTACT_INFO', name: 'Other User Contact Info', category: 'Contact Info' },

          # Health & Fitness
          { id: 'HEALTH', name: 'Health', category: 'Health & Fitness' },
          { id: 'FITNESS', name: 'Fitness', category: 'Health & Fitness' },

          # Financial Info
          { id: 'PAYMENT_INFO', name: 'Payment Info', category: 'Financial Info' },
          { id: 'CREDIT_INFO', name: 'Credit Info', category: 'Financial Info' },
          { id: 'OTHER_FINANCIAL_INFO', name: 'Other Financial Info', category: 'Financial Info' },

          # Location
          { id: 'PRECISE_LOCATION', name: 'Precise Location', category: 'Location' },
          { id: 'COARSE_LOCATION', name: 'Coarse Location', category: 'Location' },

          # Sensitive Info
          { id: 'SENSITIVE_INFO', name: 'Sensitive Info', category: 'Sensitive Info' },

          # Contacts
          { id: 'CONTACTS', name: 'Contacts', category: 'Contacts' },

          # User Content
          { id: 'EMAILS_OR_TEXT_MESSAGES', name: 'Emails or Text Messages', category: 'User Content' },
          { id: 'PHOTOS_OR_VIDEOS', name: 'Photos or Videos', category: 'User Content' },
          { id: 'AUDIO_DATA', name: 'Audio Data', category: 'User Content' },
          { id: 'GAMEPLAY_CONTENT', name: 'Gameplay Content', category: 'User Content' },
          { id: 'CUSTOMER_SUPPORT', name: 'Customer Support', category: 'User Content' },
          { id: 'OTHER_USER_CONTENT', name: 'Other User Content', category: 'User Content' },

          # Browsing History
          { id: 'BROWSING_HISTORY', name: 'Browsing History', category: 'Browsing History' },

          # Search History
          { id: 'SEARCH_HISTORY', name: 'Search History', category: 'Search History' },

          # Identifiers
          { id: 'USER_ID', name: 'User ID', category: 'Identifiers' },
          { id: 'DEVICE_ID', name: 'Device ID', category: 'Identifiers' },

          # Purchases
          { id: 'PURCHASE_HISTORY', name: 'Purchase History', category: 'Purchases' },

          # Usage Data
          { id: 'PRODUCT_INTERACTION', name: 'Product Interaction', category: 'Usage Data' },
          { id: 'ADVERTISING_DATA', name: 'Advertising Data', category: 'Usage Data' },
          { id: 'OTHER_USAGE_DATA', name: 'Other Usage Data', category: 'Usage Data' },

          # Diagnostics
          { id: 'CRASH_DATA', name: 'Crash Data', category: 'Diagnostics' },
          { id: 'PERFORMANCE_DATA', name: 'Performance Data', category: 'Diagnostics' },
          { id: 'OTHER_DIAGNOSTIC_DATA', name: 'Other Diagnostic Data', category: 'Diagnostics' },

          # Other
          { id: 'OTHER_DATA', name: 'Other Data Types', category: 'Other' }
        ]
      end

      # Reference: All available privacy purposes
      def privacy_purposes
        [
          { id: 'THIRD_PARTY_ADVERTISING', name: 'Third-Party Advertising',
            description: 'Used to display third-party ads or share with ad networks' },
          { id: 'DEVELOPERS_ADVERTISING', name: "Developer's Advertising or Marketing",
            description: 'Used to display first-party ads or marketing communications' },
          { id: 'ANALYTICS', name: 'Analytics',
            description: 'Used to evaluate user behavior or measure audience size' },
          { id: 'PRODUCT_PERSONALIZATION', name: 'Product Personalization',
            description: 'Used to customize features, content, or recommendations' },
          { id: 'APP_FUNCTIONALITY', name: 'App Functionality',
            description: 'Used for features like authentication, security, or preferences' },
          { id: 'OTHER_PURPOSES', name: 'Other Purposes',
            description: 'Used for purposes not listed above' }
        ]
      end

      # Reference: Data protection/linkage levels
      def privacy_protection_levels
        [
          { id: 'DATA_USED_TO_TRACK_YOU', name: 'Used to Track You',
            description: 'Data used for cross-app/cross-site tracking (requires ATT prompt)' },
          { id: 'DATA_LINKED_TO_YOU', name: 'Linked to You',
            description: 'Data associated with user identity (account, device, etc.)' },
          { id: 'DATA_NOT_LINKED_TO_YOU', name: 'Not Linked to You',
            description: 'Data collected but not associated with user identity' },
          { id: 'DATA_NOT_COLLECTED', name: 'Not Collected',
            description: 'Data is not collected by the app' }
        ]
      end
    end
  end
end
