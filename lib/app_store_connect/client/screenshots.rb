# frozen_string_literal: true

module AppStoreConnect
  class Client
    # App screenshot management methods
    module Screenshots
      # Get screenshot sets for a localization
      def app_screenshot_sets(localization_id:)
        get("/appStoreVersionLocalizations/#{localization_id}/appScreenshotSets")['data'].map do |set|
          {
            id: set['id'],
            screenshot_display_type: set.dig('attributes', 'screenshotDisplayType')
          }
        end
      end

      # Get screenshots in a screenshot set
      def app_screenshots(screenshot_set_id:)
        get("/appScreenshotSets/#{screenshot_set_id}/appScreenshots")['data'].map do |screenshot|
          {
            id: screenshot['id'],
            file_name: screenshot.dig('attributes', 'fileName'),
            file_size: screenshot.dig('attributes', 'fileSize'),
            upload_state: screenshot.dig('attributes', 'assetDeliveryState', 'state'),
            source_file_checksum: screenshot.dig('attributes', 'sourceFileChecksum')
          }
        end
      end

      # Create a screenshot set for a localization
      def create_app_screenshot_set(localization_id:, display_type:)
        post('/appScreenshotSets', body: {
               data: {
                 type: 'appScreenshotSets',
                 attributes: {
                   screenshotDisplayType: display_type
                 },
                 relationships: {
                   appStoreVersionLocalization: {
                     data: {
                       type: 'appStoreVersionLocalizations',
                       id: localization_id
                     }
                   }
                 }
               }
             })
      end

      # Delete a screenshot set
      def delete_app_screenshot_set(screenshot_set_id:)
        delete("/appScreenshotSets/#{screenshot_set_id}")
      end

      # Upload a screenshot to a screenshot set
      # This is a multi-step process:
      # 1. Reserve the screenshot upload
      # 2. Upload the image file
      # 3. Commit the upload
      def upload_app_screenshot(screenshot_set_id:, file_path:)
        file_name = File.basename(file_path)
        file_size = File.size(file_path)
        checksum = Digest::MD5.file(file_path).base64digest

        # Step 1: Reserve the upload
        reservation = post('/appScreenshots', body: {
                             data: {
                               type: 'appScreenshots',
                               attributes: {
                                 fileName: file_name,
                                 fileSize: file_size,
                                 sourceFileChecksum: checksum
                               },
                               relationships: {
                                 appScreenshotSet: {
                                   data: {
                                     type: 'appScreenshotSets',
                                     id: screenshot_set_id
                                   }
                                 }
                               }
                             }
                           })

        screenshot_id = reservation['data']['id']
        upload_operations = reservation['data'].dig('attributes', 'uploadOperations')

        # Step 2: Upload the file parts
        file_data = File.binread(file_path)
        upload_operations&.each do |operation|
          upload_part(
            url: operation['url'],
            data: file_data[operation['offset'], operation['length']],
            headers: operation['requestHeaders']
          )
        end

        # Step 3: Commit the upload
        patch("/appScreenshots/#{screenshot_id}", body: {
                data: {
                  type: 'appScreenshots',
                  id: screenshot_id,
                  attributes: {
                    uploaded: true,
                    sourceFileChecksum: checksum
                  }
                }
              })

        reservation
      end

      # Delete a screenshot
      def delete_app_screenshot(screenshot_id:)
        delete("/appScreenshots/#{screenshot_id}")
      end

      # Reorder screenshots in a set
      def reorder_app_screenshots(screenshot_set_id:, screenshot_ids:)
        patch("/appScreenshotSets/#{screenshot_set_id}/relationships/appScreenshots", body: {
                data: screenshot_ids.map { |id| { type: 'appScreenshots', id: id } }
              })
      end

      private

      # Upload a file part to the asset upload URL
      def upload_part(url:, data:, headers:)
        headers_hash = headers.each_with_object({}) { |h, acc| acc[h['name']] = h['value'] }

        max_retries = (@upload_retries || 0).to_i
        base_sleep = (@upload_retry_sleep || 1.0).to_f
        attempt = 0

        begin
          attempt += 1

          if defined?(CurlHttpClient) && @http_client.is_a?(CurlHttpClient)
            result = @http_client.execute(method: :put, url: url, headers: headers_hash, raw_body: data)
            status = result[:status].to_i
            raise ApiError, "Upload failed: #{status}" unless status >= 200 && status < 300
            return result
          end

          uri = URI(url)

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          configure_upload_ssl(http)

          request = Net::HTTP::Put.new(uri)
          headers_hash.each { |k, v| request[k] = v }
          request.body = data

          response = http.request(request)
          raise ApiError, "Upload failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

          response
        rescue OpenSSL::SSL::SSLError, Errno::ECONNRESET, EOFError, Net::OpenTimeout, Net::ReadTimeout,
               SocketError => e
          raise if attempt > max_retries

          # Backoff: base * attempt with a tiny jitter to avoid thundering herd
          sleep(base_sleep * attempt + rand * 0.1)
          retry
        rescue ApiError => e
          # Retry server errors and rate limiting; do not retry client errors.
          status = e.message[/Upload failed: (\d+)/, 1]&.to_i
          retriable = status && (status >= 500 || status == 429 || status == 408)

          raise if !retriable || attempt > max_retries

          sleep(base_sleep * attempt + rand * 0.1)
          retry
        end
      end

      def configure_upload_ssl(http)
        if @verify_ssl
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER

          if @skip_crl_verification
            store = OpenSSL::X509::Store.new
            store.set_default_paths

            http.verify_callback = lambda { |preverify_ok, store_context|
              return true if preverify_ok

              error_code = store_context.error
              HttpClient::CRL_ERROR_CODES.include?(error_code)
            }

            http.cert_store = store
          end
        else
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
      end
    end
  end
end
