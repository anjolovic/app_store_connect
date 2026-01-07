# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module AppStoreConnect
  # HTTP client adapter for making API requests
  # Uses Net::HTTP by default, which allows WebMock stubbing in tests
  class HttpClient
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

      # Skip CRL verification to avoid issues with Apple's certificates
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER

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
  end

  # Curl-based HTTP client for environments where Net::HTTP has SSL issues
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

      curl_cmd = build_curl_command(method, url, headers, body)
      output = `#{curl_cmd.shelljoin}`
      status = $CHILD_STATUS

      raise ApiError, "HTTP request failed with exit code #{status.exitstatus}" unless status.success?

      {
        status: 200, # curl doesn't easily give us status, assume success if exit 0
        body: parse_response_body(output)
      }
    end

    private

    def build_curl_command(method, url, headers, body)
      cmd = ['curl', '-s', '-g', '-X', method.to_s.upcase]

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
