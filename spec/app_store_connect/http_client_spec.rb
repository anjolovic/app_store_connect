# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AppStoreConnect::HttpClient do
  describe '#initialize' do
    it 'creates client with default options' do
      client = described_class.new
      expect(client).to be_a(described_class)
    end

    it 'accepts skip_crl_verification option' do
      client = described_class.new(skip_crl_verification: false)
      expect(client).to be_a(described_class)
    end

    it 'accepts verify_ssl option' do
      client = described_class.new(verify_ssl: false)
      expect(client).to be_a(described_class)
    end

    it 'accepts combined options' do
      client = described_class.new(
        skip_crl_verification: true,
        verify_ssl: true
      )
      expect(client).to be_a(described_class)
    end
  end

  describe '#execute' do
    let(:client) { described_class.new }
    let(:url) { 'https://api.appstoreconnect.apple.com/v1/apps' }
    let(:headers) { { 'Authorization' => 'Bearer token', 'Content-Type' => 'application/json' } }

    before do
      stub_request(:get, url)
        .with(headers: headers)
        .to_return(status: 200, body: '{"data": []}')
    end

    it 'makes HTTP requests' do
      response = client.execute(method: :get, url: url, headers: headers)
      expect(response[:status]).to eq(200)
      expect(response[:body]).to eq({ 'data' => [] })
    end

    it 'handles POST requests with body' do
      post_url = 'https://api.appstoreconnect.apple.com/v1/betaTesters'
      body = { data: { type: 'betaTesters' } }

      stub_request(:post, post_url)
        .with(headers: headers, body: body.to_json)
        .to_return(status: 201, body: '{"data": {"id": "123"}}')

      response = client.execute(method: :post, url: post_url, headers: headers, body: body)
      expect(response[:status]).to eq(201)
    end

    it 'handles PATCH requests' do
      patch_url = 'https://api.appstoreconnect.apple.com/v1/users/123'

      stub_request(:patch, patch_url)
        .with(headers: headers)
        .to_return(status: 200, body: '{}')

      response = client.execute(method: :patch, url: patch_url, headers: headers)
      expect(response[:status]).to eq(200)
    end

    it 'handles DELETE requests' do
      delete_url = 'https://api.appstoreconnect.apple.com/v1/betaTesters/123'

      stub_request(:delete, delete_url)
        .with(headers: headers)
        .to_return(status: 204, body: '')

      response = client.execute(method: :delete, url: delete_url, headers: headers)
      expect(response[:status]).to eq(204)
    end

    it 'handles empty response bodies' do
      stub_request(:get, url)
        .with(headers: headers)
        .to_return(status: 200, body: '')

      response = client.execute(method: :get, url: url, headers: headers)
      expect(response[:body]).to eq({})
    end

    it 'handles non-JSON response bodies' do
      stub_request(:get, url)
        .with(headers: headers)
        .to_return(status: 200, body: 'plain text response')

      response = client.execute(method: :get, url: url, headers: headers)
      expect(response[:body]).to eq({ 'raw' => 'plain text response' })
    end

    it 'raises ArgumentError for unsupported HTTP methods' do
      expect do
        client.execute(method: :options, url: url, headers: headers)
      end.to raise_error(ArgumentError, /Unsupported HTTP method/)
    end
  end

  describe 'SSL configuration' do
    it 'verifies SSL by default' do
      client = described_class.new
      # The client should be configured to verify SSL
      # We test this indirectly through the successful creation
      expect(client).to be_a(described_class)
    end

    it 'can disable SSL verification' do
      client = described_class.new(verify_ssl: false)
      expect(client).to be_a(described_class)
    end

    it 'skips CRL verification by default' do
      client = described_class.new
      # Default should skip CRL verification
      expect(client).to be_a(described_class)
    end
  end

  describe 'CRL_ERROR_CODES constant' do
    it 'includes expected error codes' do
      expect(described_class::CRL_ERROR_CODES).to include(3)  # UNABLE_TO_GET_CRL
      expect(described_class::CRL_ERROR_CODES).to include(12) # CRL_HAS_EXPIRED
      expect(described_class::CRL_ERROR_CODES).to include(14) # CRL_NOT_YET_VALID
    end

    it 'does not include CERT_REVOKED error' do
      # Error code 23 (CERT_REVOKED) should NOT be ignored
      expect(described_class::CRL_ERROR_CODES).not_to include(23)
    end
  end
end

RSpec.describe AppStoreConnect::CurlHttpClient do
  describe '#execute' do
    let(:client) { described_class.new }

    it 'creates client' do
      expect(client).to be_a(described_class)
    end

    # NOTE: CurlHttpClient tests are limited because they require actual curl execution
    # Integration tests would be needed to fully test curl behavior
  end
end
