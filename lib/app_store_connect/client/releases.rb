# frozen_string_literal: true

module AppStoreConnect
  class Client
    # Release automation and phased release methods
    module Releases
      # Create a new app store version
      # platform: IOS, MAC_OS, TV_OS, VISION_OS
      # release_type: MANUAL, AFTER_APPROVAL, SCHEDULED
      def create_app_store_version(version_string:, platform: 'IOS', release_type: 'AFTER_APPROVAL',
                                   earliest_release_date: nil, target_app_id: nil)
        target_app_id ||= @app_id

        attributes = {
          versionString: version_string,
          platform: platform,
          releaseType: release_type
        }

        # For SCHEDULED release type, set the earliest release date
        attributes[:earliestReleaseDate] = earliest_release_date if earliest_release_date && release_type == 'SCHEDULED'

        result = post('/appStoreVersions', body: {
                        data: {
                          type: 'appStoreVersions',
                          attributes: attributes,
                          relationships: {
                            app: {
                              data: {
                                type: 'apps',
                                id: target_app_id
                              }
                            }
                          }
                        }
                      })

        {
          id: result['data']['id'],
          version_string: result['data'].dig('attributes', 'versionString'),
          state: result['data'].dig('attributes', 'appStoreState'),
          release_type: result['data'].dig('attributes', 'releaseType'),
          created_date: result['data'].dig('attributes', 'createdDate')
        }
      end

      # Update app store version settings
      def update_app_store_version(version_id:, release_type: nil, earliest_release_date: nil,
                                   version_string: nil, downloadable: nil)
        attributes = {}
        attributes[:releaseType] = release_type if release_type
        attributes[:earliestReleaseDate] = earliest_release_date if earliest_release_date
        attributes[:versionString] = version_string if version_string
        attributes[:downloadable] = downloadable unless downloadable.nil?

        return nil if attributes.empty?

        patch("/appStoreVersions/#{version_id}", body: {
                data: {
                  type: 'appStoreVersions',
                  id: version_id,
                  attributes: attributes
                }
              })
      end

      # Get phased release info for a version
      def phased_release(version_id:)
        result = get("/appStoreVersions/#{version_id}/appStoreVersionPhasedRelease")['data']
        return nil unless result

        {
          id: result['id'],
          state: result.dig('attributes', 'phasedReleaseState'),
          start_date: result.dig('attributes', 'startDate'),
          total_pause_duration: result.dig('attributes', 'totalPauseDuration'),
          current_day_number: result.dig('attributes', 'currentDayNumber')
        }
      rescue ApiError => e
        return nil if e.message.include?('Not found')

        raise
      end

      # Enable phased release for a version (7-day gradual rollout)
      def create_phased_release(version_id:)
        result = post('/appStoreVersionPhasedReleases', body: {
                        data: {
                          type: 'appStoreVersionPhasedReleases',
                          attributes: {
                            phasedReleaseState: 'INACTIVE'
                          },
                          relationships: {
                            appStoreVersion: {
                              data: {
                                type: 'appStoreVersions',
                                id: version_id
                              }
                            }
                          }
                        }
                      })

        {
          id: result['data']['id'],
          state: result['data'].dig('attributes', 'phasedReleaseState')
        }
      end

      # Update phased release state
      # state: INACTIVE, ACTIVE, PAUSED, COMPLETE
      def update_phased_release(phased_release_id:, state:)
        patch("/appStoreVersionPhasedReleases/#{phased_release_id}", body: {
                data: {
                  type: 'appStoreVersionPhasedReleases',
                  id: phased_release_id,
                  attributes: {
                    phasedReleaseState: state
                  }
                }
              })
      end

      # Delete phased release (disable gradual rollout)
      def delete_phased_release(phased_release_id:)
        delete("/appStoreVersionPhasedReleases/#{phased_release_id}")
      end

      # Release a version that's pending developer release
      def release_version(version_id:)
        versions = app_store_versions
        version = versions.find { |v| v['id'] == version_id }

        raise ApiError, "Version not found: #{version_id}" unless version

        state = version.dig('attributes', 'appStoreState')
        raise ApiError, "Version must be PENDING_DEVELOPER_RELEASE to release (current: #{state})" unless state == 'PENDING_DEVELOPER_RELEASE'

        patch("/appStoreVersions/#{version_id}", body: {
                data: {
                  type: 'appStoreVersions',
                  id: version_id,
                  attributes: {
                    releaseType: 'AFTER_APPROVAL'
                  }
                }
              })
      end

      # ─────────────────────────────────────────────────────────────────────────
      # Pre-Order Management
      # ─────────────────────────────────────────────────────────────────────────

      # Get pre-order info for an app
      def pre_order(target_app_id: nil)
        target_app_id ||= @app_id
        result = get("/apps/#{target_app_id}/preOrder")['data']
        return nil unless result

        {
          id: result['id'],
          pre_order_available_date: result.dig('attributes', 'preOrderAvailableDate'),
          app_release_date: result.dig('attributes', 'appReleaseDate')
        }
      rescue ApiError => e
        return nil if e.message.include?('Not found')

        raise
      end

      # Enable pre-order for an app
      def create_pre_order(app_release_date:, target_app_id: nil)
        target_app_id ||= @app_id

        result = post('/appPreOrders', body: {
                        data: {
                          type: 'appPreOrders',
                          attributes: {
                            appReleaseDate: app_release_date
                          },
                          relationships: {
                            app: {
                              data: {
                                type: 'apps',
                                id: target_app_id
                              }
                            }
                          }
                        }
                      })

        {
          id: result['data']['id'],
          app_release_date: result['data'].dig('attributes', 'appReleaseDate')
        }
      end

      # Update pre-order release date
      def update_pre_order(pre_order_id:, app_release_date:)
        patch("/appPreOrders/#{pre_order_id}", body: {
                data: {
                  type: 'appPreOrders',
                  id: pre_order_id,
                  attributes: {
                    appReleaseDate: app_release_date
                  }
                }
              })
      end

      # Delete pre-order (cancel pre-order availability)
      def delete_pre_order(pre_order_id:)
        delete("/appPreOrders/#{pre_order_id}")
      end
    end
  end
end
