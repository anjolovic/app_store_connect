# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require 'openssl'

module AppStoreConnect
  # HTTP client adapter for making API requests
  # Uses Net::HTTP by default, which allows WebMock stubbing in tests
  #
  # Handles SSL/TLS certificate verification with special handling for CRL
  # (Certificate Revocation List) verification issues that can occur with
  # Apple's App Store Connect API certificates.
  class HttpClient
    # CRL-related OpenSSL error codes that should be ignored
    # These errors indicate CRL verification failures, not actual security issues
    # Note: We do NOT include error code 23 (X509_V_ERR_CERT_REVOKED) because
    # revoked certificates should always fail verification
    CRL_ERROR_CODES = [
      3,  # X509_V_ERR_UNABLE_TO_GET_CRL - unable to get certificate CRL
      12, # X509_V_ERR_CRL_HAS_EXPIRED - CRL has expired
      13, # X509_V_ERR_CERT_NOT_YET_VALID - certificate is not yet valid (clock skew)
      14  # X509_V_ERR_CRL_NOT_YET_VALID - CRL is not yet valid
    ].freeze

    # @param skip_crl_verification [Boolean] Whether to skip CRL verification (default: true)
    # @param verify_ssl [Boolean] Whether to verify SSL certificates (default: true)
    def initialize(skip_crl_verification: true, verify_ssl: true)
      @skip_crl_verification = skip_crl_verification
      @verify_ssl = verify_ssl
    end

    # Executes an HTTP request
    #
    # @param method [Symbol] HTTP method (:get, :post, :patch, :delete)
    # @param url [String] Full URL to request
    # @param headers [Hash] Request headers
    # @param body [Hash, nil] Request body (will be JSON encoded)
    # @return [Hash] Parsed JSON response with :status and :body keys
    def execute(method:, url:, headers:, body: nil)
      uri = URI(url)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 30
      http.read_timeout = 60

      configure_ssl(http)

      request = build_request(method, uri, headers, body)
      response = http.request(request)

      {
        status: response.code.to_i,
        body: parse_response_body(response.body)
      }
    end

    private

    def build_request(method, uri, headers, body)
      request_class = case method
                      when :get then Net::HTTP::Get
                      when :post then Net::HTTP::Post
                      when :patch then Net::HTTP::Patch
                      when :delete then Net::HTTP::Delete
                      when :put then Net::HTTP::Put
                      else
                        raise ArgumentError, "Unsupported HTTP method: #{method}"
                      end

      request = request_class.new(uri)
      headers.each { |key, value| request[key] = value }
      request.body = body.to_json if body
      request
    end

    def parse_response_body(body)
      return {} if body.nil? || body.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      { 'raw' => body }
    end

    def configure_ssl(http)
      if @verify_ssl
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER

        if @skip_crl_verification
          # Create a certificate store that doesn't check CRLs
          # This avoids issues with Apple's certificates that may have
          # unreachable or expired CRL distribution points
          store = OpenSSL::X509::Store.new
          store.set_default_paths

          # Set verify callback to handle CRL errors gracefully
          # This still verifies the certificate chain, just ignores CRL issues
          http.verify_callback = lambda { |preverify_ok, store_context|
            return true if preverify_ok

            error_code = store_context.error

            # If the error is CRL-related, ignore it and continue
            if CRL_ERROR_CODES.include?(error_code)
              true
            else
              # For other errors, fail the verification
              false
            end
          }

          http.cert_store = store
        end
      else
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
    end
  end

  # Curl-based HTTP client for environments where Net::HTTP has SSL issues
  # This client uses curl which handles SSL/CRL verification more robustly
  # on some systems. It properly captures HTTP status codes for error handling.
  class CurlHttpClient
    # Executes an HTTP request using curl
    #
    # @param method [Symbol] HTTP method (:get, :post, :patch, :delete)
    # @param url [String] Full URL to request
    # @param headers [Hash] Request headers
    # @param body [Hash, nil] Request body (will be JSON encoded)
    # @return [Hash] Parsed JSON response with :status and :body keys
    def execute(method:, url:, headers:, body: nil)
      require 'shellwords'
      require 'tempfile'

      # Use a temp file to capture response body, and -w to get status code
      Tempfile.create('curl_response') do |response_file|
        curl_cmd = build_curl_command(method, url, headers, body, response_file.path)
        status_output = `#{curl_cmd.shelljoin}`
        exit_status = $CHILD_STATUS

        unless exit_status.success?
          raise ApiError, "HTTP request failed: curl exit code #{exit_status.exitstatus}"
        end

        http_status = status_output.strip.to_i
        response_body = File.read(response_file.path)

        {
          status: http_status,
          body: parse_response_body(response_body)
        }
      end
    end

    private

    def build_curl_command(method, url, headers, body, output_file)
      cmd = [
        'curl',
        '-s',           # Silent mode
        '-g',           # Disable URL globbing (for brackets in URLs)
        '-o', output_file,  # Write response body to file
        '-w', '%{http_code}', # Write HTTP status code to stdout
        '-X', method.to_s.upcase
      ]

      headers.each do |key, value|
        cmd += ['-H', "#{key}: #{value}"]
      end

      cmd += ['-d', body.to_json] if body
      cmd << url

      cmd
    end

    def parse_response_body(body)
      return {} if body.nil? || body.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      { 'raw' => body }
    end
  end
end
