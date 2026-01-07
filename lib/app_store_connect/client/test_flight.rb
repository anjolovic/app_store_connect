# frozen_string_literal: true

module AppStoreConnect
  class Client
    # TestFlight beta testing methods
    module TestFlight
      # ─────────────────────────────────────────────────────────────────────────
      # Beta Testers
      # ─────────────────────────────────────────────────────────────────────────

      # List all beta testers for an app
      def beta_testers(target_app_id: nil, limit: 100)
        target_app_id ||= @app_id
        get("/betaTesters?filter[apps]=#{target_app_id}&limit=#{limit}")['data'].map do |tester|
          {
            id: tester['id'],
            email: tester.dig('attributes', 'email'),
            first_name: tester.dig('attributes', 'firstName'),
            last_name: tester.dig('attributes', 'lastName'),
            invite_type: tester.dig('attributes', 'inviteType'),
            state: tester.dig('attributes', 'state')
          }
        end
      end

      # Get a single beta tester by ID
      def beta_tester(tester_id:)
        tester = get("/betaTesters/#{tester_id}")['data']
        {
          id: tester['id'],
          email: tester.dig('attributes', 'email'),
          first_name: tester.dig('attributes', 'firstName'),
          last_name: tester.dig('attributes', 'lastName'),
          invite_type: tester.dig('attributes', 'inviteType'),
          state: tester.dig('attributes', 'state')
        }
      end

      # Invite a new beta tester
      def create_beta_tester(email:, first_name: nil, last_name: nil, group_ids: [], target_app_id: nil)
        target_app_id ||= @app_id

        attributes = { email: email }
        attributes[:firstName] = first_name if first_name
        attributes[:lastName] = last_name if last_name

        relationships = {}

        # Add to beta groups if specified
        if group_ids.any?
          relationships[:betaGroups] = {
            data: group_ids.map { |id| { type: 'betaGroups', id: id } }
          }
        else
          # If no groups specified, add to app directly
          relationships[:apps] = {
            data: [{ type: 'apps', id: target_app_id }]
          }
        end

        result = post('/betaTesters', body: {
                        data: {
                          type: 'betaTesters',
                          attributes: attributes,
                          relationships: relationships
                        }
                      })

        {
          id: result['data']['id'],
          email: result['data'].dig('attributes', 'email'),
          state: result['data'].dig('attributes', 'betaTestersState')
        }
      end

      # Remove a beta tester from the app
      def delete_beta_tester(tester_id:)
        delete("/betaTesters/#{tester_id}")
      end

      # Add tester to beta groups
      def add_tester_to_groups(tester_id:, group_ids:)
        post("/betaTesters/#{tester_id}/relationships/betaGroups", body: {
               data: group_ids.map { |id| { type: 'betaGroups', id: id } }
             })
      end

      # Remove tester from beta groups
      def remove_tester_from_groups(tester_id:, group_ids:)
        delete_with_body("/betaTesters/#{tester_id}/relationships/betaGroups", body: {
                           data: group_ids.map { |id| { type: 'betaGroups', id: id } }
                         })
      end

      # ─────────────────────────────────────────────────────────────────────────
      # Beta Groups
      # ─────────────────────────────────────────────────────────────────────────

      # List all beta groups for an app
      def beta_groups(target_app_id: nil)
        target_app_id ||= @app_id
        get("/apps/#{target_app_id}/betaGroups")['data'].map do |group|
          {
            id: group['id'],
            name: group.dig('attributes', 'name'),
            is_internal: group.dig('attributes', 'isInternalGroup'),
            public_link_enabled: group.dig('attributes', 'publicLinkEnabled'),
            public_link: group.dig('attributes', 'publicLink'),
            public_link_limit: group.dig('attributes', 'publicLinkLimit'),
            public_link_limit_enabled: group.dig('attributes', 'publicLinkLimitEnabled'),
            created_date: group.dig('attributes', 'createdDate')
          }
        end
      end

      # Get a single beta group
      def beta_group(group_id:)
        group = get("/betaGroups/#{group_id}")['data']
        {
          id: group['id'],
          name: group.dig('attributes', 'name'),
          is_internal: group.dig('attributes', 'isInternalGroup'),
          public_link_enabled: group.dig('attributes', 'publicLinkEnabled'),
          public_link: group.dig('attributes', 'publicLink'),
          public_link_limit: group.dig('attributes', 'publicLinkLimit'),
          public_link_limit_enabled: group.dig('attributes', 'publicLinkLimitEnabled'),
          created_date: group.dig('attributes', 'createdDate')
        }
      end

      # Create a new beta group
      def create_beta_group(name:, public_link_enabled: false, public_link_limit: nil,
                            public_link_limit_enabled: false, feedback_enabled: true, target_app_id: nil)
        target_app_id ||= @app_id

        attributes = {
          name: name,
          publicLinkEnabled: public_link_enabled,
          publicLinkLimitEnabled: public_link_limit_enabled,
          feedbackEnabled: feedback_enabled
        }
        attributes[:publicLinkLimit] = public_link_limit if public_link_limit

        result = post('/betaGroups', body: {
                        data: {
                          type: 'betaGroups',
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
          name: result['data'].dig('attributes', 'name'),
          public_link: result['data'].dig('attributes', 'publicLink')
        }
      end

      # Update a beta group
      def update_beta_group(group_id:, name: nil, public_link_enabled: nil,
                            public_link_limit: nil, public_link_limit_enabled: nil, feedback_enabled: nil)
        attributes = {}
        attributes[:name] = name if name
        attributes[:publicLinkEnabled] = public_link_enabled unless public_link_enabled.nil?
        attributes[:publicLinkLimit] = public_link_limit if public_link_limit
        attributes[:publicLinkLimitEnabled] = public_link_limit_enabled unless public_link_limit_enabled.nil?
        attributes[:feedbackEnabled] = feedback_enabled unless feedback_enabled.nil?

        return nil if attributes.empty?

        patch("/betaGroups/#{group_id}", body: {
                data: {
                  type: 'betaGroups',
                  id: group_id,
                  attributes: attributes
                }
              })
      end

      # Delete a beta group
      def delete_beta_group(group_id:)
        delete("/betaGroups/#{group_id}")
      end

      # Get testers in a beta group
      def beta_group_testers(group_id:, limit: 100)
        get("/betaGroups/#{group_id}/betaTesters?limit=#{limit}")['data'].map do |tester|
          {
            id: tester['id'],
            email: tester.dig('attributes', 'email'),
            first_name: tester.dig('attributes', 'firstName'),
            last_name: tester.dig('attributes', 'lastName'),
            state: tester.dig('attributes', 'state')
          }
        end
      end

      # Add testers to a beta group
      def add_testers_to_group(group_id:, tester_ids:)
        post("/betaGroups/#{group_id}/relationships/betaTesters", body: {
               data: tester_ids.map { |id| { type: 'betaTesters', id: id } }
             })
      end

      # Remove testers from a beta group
      def remove_testers_from_group(group_id:, tester_ids:)
        delete_with_body("/betaGroups/#{group_id}/relationships/betaTesters", body: {
                           data: tester_ids.map { |id| { type: 'betaTesters', id: id } }
                         })
      end

      # ─────────────────────────────────────────────────────────────────────────
      # Build Distribution
      # ─────────────────────────────────────────────────────────────────────────

      # Get builds available for TestFlight
      def testflight_builds(target_app_id: nil, limit: 20)
        target_app_id ||= @app_id
        get("/builds?filter[app]=#{target_app_id}&limit=#{limit}&sort=-uploadedDate")['data'].map do |build|
          {
            id: build['id'],
            version: build.dig('attributes', 'version'),
            uploaded_date: build.dig('attributes', 'uploadedDate'),
            processing_state: build.dig('attributes', 'processingState'),
            uses_non_exempt_encryption: build.dig('attributes', 'usesNonExemptEncryption'),
            expired: build.dig('attributes', 'expired')
          }
        end
      end

      # Get beta build details (TestFlight-specific info)
      def beta_build_detail(build_id:)
        result = get("/builds/#{build_id}/buildBetaDetail")['data']
        return nil unless result

        {
          id: result['id'],
          auto_notify_enabled: result.dig('attributes', 'autoNotifyEnabled'),
          internal_build_state: result.dig('attributes', 'internalBuildState'),
          external_build_state: result.dig('attributes', 'externalBuildState')
        }
      rescue ApiError => e
        return nil if e.message.include?('Not found')

        raise
      end

      # Update beta build details (enable/disable auto-notify)
      def update_beta_build_detail(beta_detail_id:, auto_notify_enabled:)
        patch("/buildBetaDetails/#{beta_detail_id}", body: {
                data: {
                  type: 'buildBetaDetails',
                  id: beta_detail_id,
                  attributes: {
                    autoNotifyEnabled: auto_notify_enabled
                  }
                }
              })
      end

      # Add build to beta groups (distribute to testers)
      def add_build_to_groups(build_id:, group_ids:)
        post("/builds/#{build_id}/relationships/betaGroups", body: {
               data: group_ids.map { |id| { type: 'betaGroups', id: id } }
             })
      end

      # Remove build from beta groups
      def remove_build_from_groups(build_id:, group_ids:)
        delete_with_body("/builds/#{build_id}/relationships/betaGroups", body: {
                           data: group_ids.map { |id| { type: 'betaGroups', id: id } }
                         })
      end

      # Get beta groups a build is distributed to
      def build_beta_groups(build_id:)
        get("/builds/#{build_id}/betaGroups")['data'].map do |group|
          {
            id: group['id'],
            name: group.dig('attributes', 'name'),
            is_internal: group.dig('attributes', 'isInternalGroup')
          }
        end
      end

      # ─────────────────────────────────────────────────────────────────────────
      # Beta Build Localizations (What's New)
      # ─────────────────────────────────────────────────────────────────────────

      # Get beta build localizations (What's New text for TestFlight)
      def beta_build_localizations(build_id:)
        get("/builds/#{build_id}/betaBuildLocalizations")['data'].map do |loc|
          {
            id: loc['id'],
            locale: loc.dig('attributes', 'locale'),
            whats_new: loc.dig('attributes', 'whatsNew')
          }
        end
      end

      # Create beta build localization
      def create_beta_build_localization(build_id:, locale:, whats_new:)
        result = post('/betaBuildLocalizations', body: {
                        data: {
                          type: 'betaBuildLocalizations',
                          attributes: {
                            locale: locale,
                            whatsNew: whats_new
                          },
                          relationships: {
                            build: {
                              data: {
                                type: 'builds',
                                id: build_id
                              }
                            }
                          }
                        }
                      })

        {
          id: result['data']['id'],
          locale: result['data'].dig('attributes', 'locale'),
          whats_new: result['data'].dig('attributes', 'whatsNew')
        }
      end

      # Update beta build localization
      def update_beta_build_localization(localization_id:, whats_new:)
        patch("/betaBuildLocalizations/#{localization_id}", body: {
                data: {
                  type: 'betaBuildLocalizations',
                  id: localization_id,
                  attributes: {
                    whatsNew: whats_new
                  }
                }
              })
      end

      # ─────────────────────────────────────────────────────────────────────────
      # Beta App Review Submission
      # ─────────────────────────────────────────────────────────────────────────

      # Submit a build for beta app review (required for external testers)
      def submit_for_beta_review(build_id:)
        post('/betaAppReviewSubmissions', body: {
               data: {
                 type: 'betaAppReviewSubmissions',
                 relationships: {
                   build: {
                     data: {
                       type: 'builds',
                       id: build_id
                     }
                   }
                 }
               }
             })
      end

      # Get beta app review submission status
      def beta_app_review_submission(build_id:)
        result = get("/builds/#{build_id}/betaAppReviewSubmission")['data']
        return nil unless result

        {
          id: result['id'],
          beta_review_state: result.dig('attributes', 'betaReviewState'),
          submitted_date: result.dig('attributes', 'submittedDate')
        }
      rescue ApiError => e
        return nil if e.message.include?('Not found')

        raise
      end
    end
  end
end
