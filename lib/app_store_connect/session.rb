# frozen_string_literal: true

require 'yaml'
require 'cgi'

module AppStoreConnect
  # Session management for App Store Connect web authentication
  # Uses FASTLANE_SESSION environment variable for cookie-based auth
  #
  # Usage:
  #   1. Install fastlane: gem install fastlane
  #   2. Run: fastlane spaceauth -u your@apple.id
  #   3. Copy the session and set: export FASTLANE_SESSION="..."
  #   4. Now rejection messages will be available
  #
  class Session
    COOKIE_DOMAIN = '.apple.com'
    SESSION_FILE = File.expand_path('~/.app_store_connect_session')

    attr_reader :cookies

    def initialize
      @cookies = {}
      load_session
    end

    # Check if we have a valid session
    def valid?
      @cookies.any? && @cookies.key?('myacinfo')
    end

    # Get cookie header for requests
    def cookie_header
      @cookies.map { |k, v| "#{k}=#{v}" }.join('; ')
    end

    # Load session from FASTLANE_SESSION env var or file
    def load_session
      session_data = ENV['FASTLANE_SESSION'] || read_session_file

      return unless session_data

      parse_fastlane_session(session_data)
    end

    # Save session to file for reuse
    def save_session(session_data)
      File.write(SESSION_FILE, session_data)
      File.chmod(0o600, SESSION_FILE)
    end

    # Clear stored session
    def clear_session
      @cookies = {}
      FileUtils.rm_f(SESSION_FILE)
    end

    private

    def read_session_file
      return nil unless File.exist?(SESSION_FILE)

      File.read(SESSION_FILE)
    rescue StandardError
      nil
    end

    # Parse FASTLANE_SESSION YAML format into cookies hash
    def parse_fastlane_session(session_data)
      # FASTLANE_SESSION is a YAML-encoded array of cookie strings
      # Format: "---\n- !ruby/object:HTTP::Cookie\n  name: myacinfo\n  value: ..."
      # Or simpler format: just cookie strings

      # Try to parse as YAML first
      parsed = YAML.safe_load(session_data, permitted_classes: [Symbol])

      if parsed.is_a?(Array)
        parsed.each do |cookie_str|
          parse_cookie_string(cookie_str.to_s)
        end
      elsif parsed.is_a?(String)
        parse_cookie_string(parsed)
      end
    rescue Psych::DisallowedClass
      # YAML contains Ruby objects (HTTP::Cookie) - parse manually
      parse_fastlane_yaml_cookies(session_data)
    rescue StandardError
      # Try parsing as raw cookie string
      parse_cookie_string(session_data)
    end

    # Parse fastlane's YAML format with HTTP::Cookie objects
    def parse_fastlane_yaml_cookies(session_data)
      # Extract name and value pairs from the YAML structure
      current_name = nil

      session_data.each_line do |line|
        line = line.strip

        if line.start_with?('name:')
          current_name = line.sub('name:', '').strip
        elsif line.start_with?('value:') && current_name
          value = line.sub('value:', '').strip
          @cookies[current_name] = value
          current_name = nil
        end
      end
    end

    # Parse a cookie string like "name=value; name2=value2"
    def parse_cookie_string(cookie_str)
      return if cookie_str.nil? || cookie_str.empty?

      cookie_str.split(';').each do |part|
        part = part.strip
        next if part.empty?

        next unless part.include?('=')

        name, value = part.split('=', 2)
        name = name.strip
        value = value&.strip || ''

        # Skip cookie attributes
        next if %w[path domain expires max-age secure httponly samesite].include?(name.downcase)

        @cookies[name] = value
      end
    end
  end
end
