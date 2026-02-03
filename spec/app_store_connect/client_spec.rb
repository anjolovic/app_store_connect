# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AppStoreConnect::Client do
  # Create a test private key for JWT signing
  let(:private_key) do
    OpenSSL::PKey::EC.generate('prime256v1')
  end

  let(:key_file) do
    file = Tempfile.new(['test_key', '.p8'])
    file.write(private_key.to_pem)
    file.rewind
    file
  end

  let(:client) do
    described_class.new(
      key_id: 'TEST_KEY_ID',
      issuer_id: 'TEST_ISSUER_ID',
      private_key_path: key_file.path,
      app_id: '123456789',
      bundle_id: 'com.example.testapp'
    )
  end

  after do
    key_file.close
    key_file.unlink
  end

  describe '#initialize' do
    it 'accepts configuration parameters' do
      expect(client).to be_a(described_class)
    end

    context 'with global configuration' do
      before do
        AppStoreConnect.configure do |config|
          config.key_id = 'GLOBAL_KEY'
          config.issuer_id = 'GLOBAL_ISSUER'
          config.private_key_path = key_file.path
          config.app_id = '987654321'
        end
      end

      it 'uses global configuration when no params provided' do
        global_client = described_class.new
        expect(global_client).to be_a(described_class)
      end
    end

    context 'with SSL configuration' do
      it 'accepts skip_crl_verification option' do
        ssl_client = described_class.new(
          key_id: 'TEST_KEY_ID',
          issuer_id: 'TEST_ISSUER_ID',
          private_key_path: key_file.path,
          skip_crl_verification: false
        )
        expect(ssl_client).to be_a(described_class)
      end

      it 'accepts verify_ssl option' do
        ssl_client = described_class.new(
          key_id: 'TEST_KEY_ID',
          issuer_id: 'TEST_ISSUER_ID',
          private_key_path: key_file.path,
          verify_ssl: false
        )
        expect(ssl_client).to be_a(described_class)
      end

      it 'accepts use_curl option' do
        curl_client = described_class.new(
          key_id: 'TEST_KEY_ID',
          issuer_id: 'TEST_ISSUER_ID',
          private_key_path: key_file.path,
          use_curl: true
        )
        expect(curl_client).to be_a(described_class)
      end
    end
  end

  describe '#apps' do
    before do
      stub_api_get('/apps', response_body: sample_apps_response)
    end

    it 'returns a list of apps' do
      apps = client.apps
      expect(apps).to be_an(Array)
      expect(apps.length).to eq(1)
    end

    it 'returns app with correct attributes' do
      app = client.apps.first
      expect(app[:id]).to eq('123456789')
      expect(app[:name]).to eq('Test App')
    end
  end

  describe '#app_store_versions' do
    before do
      stub_api_get(
        '/apps/123456789/appStoreVersions',
        response_body: sample_versions_response
      )
    end

    it 'returns a list of versions' do
      versions = client.app_store_versions
      expect(versions).to be_an(Array)
      expect(versions.length).to eq(1)
    end

    it 'returns version with correct attributes' do
      version = client.app_store_versions.first
      expect(version['id']).to eq('ver123')
      expect(version.dig('attributes', 'versionString')).to eq('1.0.0')
      expect(version.dig('attributes', 'appStoreState')).to eq('READY_FOR_SALE')
    end
  end

  describe '#beta_testers' do
    before do
      stub_api_get(
        '/betaTesters?filter[apps]=123456789&limit=100',
        response_body: sample_beta_testers_response
      )
    end

    it 'returns a list of beta testers' do
      testers = client.beta_testers
      expect(testers).to be_an(Array)
      expect(testers.length).to eq(1)
    end

    it 'returns tester with correct attributes' do
      tester = client.beta_testers.first
      expect(tester[:id]).to eq('tester123')
      expect(tester[:email]).to eq('tester@example.com')
      expect(tester[:first_name]).to eq('Test')
      expect(tester[:last_name]).to eq('User')
    end
  end

  describe '#create_beta_tester' do
    let(:new_tester_response) do
      {
        data: {
          id: 'new_tester123',
          type: 'betaTesters',
          attributes: {
            email: 'new@example.com',
            firstName: 'New',
            lastName: 'Tester',
            inviteType: 'EMAIL',
            betaTestersState: 'INVITED'
          }
        }
      }
    end

    before do
      stub_api_post('/betaTesters', response_body: new_tester_response)
    end

    it 'creates a new beta tester' do
      result = client.create_beta_tester(
        email: 'new@example.com',
        first_name: 'New',
        last_name: 'Tester'
      )

      expect(result[:id]).to eq('new_tester123')
      expect(result[:email]).to eq('new@example.com')
      expect(result[:state]).to eq('INVITED')
    end
  end

  describe '#delete_beta_tester' do
    before do
      stub_api_delete('/betaTesters/tester123')
    end

    it 'deletes the beta tester' do
      expect { client.delete_beta_tester(tester_id: 'tester123') }.not_to raise_error
    end
  end

  describe '#beta_groups' do
    before do
      stub_api_get(
        '/apps/123456789/betaGroups',
        response_body: sample_beta_groups_response
      )
    end

    it 'returns a list of beta groups' do
      groups = client.beta_groups
      expect(groups).to be_an(Array)
      expect(groups.length).to eq(1)
    end

    it 'returns group with correct attributes' do
      group = client.beta_groups.first
      expect(group[:id]).to eq('group123')
      expect(group[:name]).to eq('External Testers')
      expect(group[:is_internal]).to be false
      expect(group[:public_link_enabled]).to be true
    end
  end

  describe '#create_subscription_group' do
    let(:subscription_group_response) do
      {
        data: {
          id: 'sub_group_1',
          type: 'subscriptionGroups',
          attributes: {
            referenceName: 'Main Plans'
          }
        }
      }
    end

    before do
      stub_api_post('/subscriptionGroups', response_body: subscription_group_response)
    end

    it 'creates a subscription group' do
      result = client.create_subscription_group(reference_name: 'Main Plans')

      expect(result[:id]).to eq('sub_group_1')
      expect(result[:reference_name]).to eq('Main Plans')
    end
  end

  describe '#create_subscription' do
    let(:subscription_response) do
      {
        data: {
          id: 'sub_1',
          type: 'subscriptions',
          attributes: {
            name: 'Monthly Plan',
            productId: 'com.example.app.plan.monthly',
            state: 'READY_TO_SUBMIT',
            groupLevel: 1,
            subscriptionPeriod: 'ONE_MONTH'
          }
        }
      }
    end

    before do
      stub_api_post('/subscriptions', response_body: subscription_response)
    end

    it 'creates a subscription product' do
      result = client.create_subscription(
        subscription_group_id: 'sub_group_1',
        name: 'Monthly Plan',
        product_id: 'com.example.app.plan.monthly',
        subscription_period: 'ONE_MONTH',
        family_sharable: true,
        review_note: 'Review note',
        group_level: 1
      )

      expect(result[:id]).to eq('sub_1')
      expect(result[:product_id]).to eq('com.example.app.plan.monthly')
      expect(result[:name]).to eq('Monthly Plan')
      expect(result[:subscription_period]).to eq('ONE_MONTH')
      expect(result[:group_level]).to eq(1)
    end
  end

  describe '#create_subscription_price' do
    let(:subscription_price_response) do
      {
        data: {
          id: 'sub_price_1',
          type: 'subscriptionPrices',
          attributes: {
            startDate: '2026-03-01'
          },
          relationships: {
            subscriptionPricePoint: {
              data: { id: 'price_point_1', type: 'subscriptionPricePoints' }
            }
          }
        }
      }
    end

    before do
      stub_api_post('/subscriptionPrices', response_body: subscription_price_response)
    end

    it 'creates a subscription price' do
      result = client.create_subscription_price(
        subscription_id: 'sub_1',
        subscription_price_point_id: 'price_point_1',
        start_date: '2026-03-01'
      )

      expect(result[:id]).to eq('sub_price_1')
      expect(result[:price_point_id]).to eq('price_point_1')
      expect(result[:start_date]).to eq('2026-03-01')
    end
  end

  describe '#create_subscription_introductory_offer' do
    let(:intro_offer_response) do
      {
        data: {
          id: 'intro_1',
          type: 'subscriptionIntroductoryOffers',
          attributes: {
            offerMode: 'FREE_TRIAL',
            duration: 'ONE_WEEK'
          },
          relationships: {
            subscriptionPricePoint: {
              data: { id: 'price_point_1', type: 'subscriptionPricePoints' }
            }
          }
        }
      }
    end

    before do
      stub_api_post('/subscriptionIntroductoryOffers', response_body: intro_offer_response)
    end

    it 'creates an introductory offer' do
      result = client.create_subscription_introductory_offer(
        subscription_id: 'sub_1',
        offer_mode: 'FREE_TRIAL',
        duration: 'ONE_WEEK',
        subscription_price_point_id: 'price_point_1'
      )

      expect(result[:id]).to eq('intro_1')
      expect(result[:offer_mode]).to eq('FREE_TRIAL')
      expect(result[:duration]).to eq('ONE_WEEK')
      expect(result[:price_point_id]).to eq('price_point_1')
    end
  end

  describe '#tax_categories' do
    let(:tax_categories_response) do
      {
        data: [
          { id: 'TAX001', type: 'taxCategories', attributes: { name: 'Standard' } },
          { id: 'TAX002', type: 'taxCategories', attributes: { name: 'Reduced' } }
        ]
      }
    end

    it 'returns a list of tax categories' do
      stub_api_get('/taxCategories?limit=200', response_body: tax_categories_response)
      categories = client.tax_categories
      expect(categories.length).to eq(2)
      expect(categories.first[:id]).to eq('TAX001')
      expect(categories.first[:name]).to eq('Standard')
    end

    it 'falls back to app-scoped tax categories when global endpoint is missing' do
      stub_api_get(
        '/taxCategories?limit=200',
        response_body: sample_error_response(title: 'Not Found', detail: 'resource does not exist'),
        status: 404
      )
      stub_api_get(
        '/apps/123456789/taxCategories?limit=200',
        response_body: tax_categories_response
      )

      categories = client.tax_categories
      expect(categories.length).to eq(2)
      expect(categories.first[:id]).to eq('TAX001')
    end

    it 'raises a helpful error when app id is missing and global endpoint is missing' do
      no_app_client = described_class.new(
        key_id: 'TEST_KEY_ID',
        issuer_id: 'TEST_ISSUER_ID',
        private_key_path: key_file.path
      )

      stub_api_get(
        '/taxCategories?limit=200',
        response_body: sample_error_response(title: 'Not Found', detail: 'resource does not exist'),
        status: 404
      )

      expect { no_app_client.tax_categories }.to raise_error(
        AppStoreConnect::ApiError,
        /APP_STORE_CONNECT_APP_ID/
      )
    end
  end

  describe '#create_beta_group' do
    let(:new_group_response) do
      {
        data: {
          id: 'new_group123',
          type: 'betaGroups',
          attributes: {
            name: 'New Group',
            isInternalGroup: false,
            publicLinkEnabled: false,
            createdDate: '2025-01-06T00:00:00Z'
          }
        }
      }
    end

    before do
      stub_api_post('/betaGroups', response_body: new_group_response)
    end

    it 'creates a new beta group' do
      result = client.create_beta_group(name: 'New Group')

      expect(result[:id]).to eq('new_group123')
      expect(result[:name]).to eq('New Group')
    end
  end

  describe '#users' do
    before do
      stub_api_get('/users?limit=100', response_body: sample_users_response)
    end

    it 'returns a list of users' do
      users = client.users
      expect(users).to be_an(Array)
      expect(users.length).to eq(1)
    end

    it 'returns user with correct attributes' do
      user = client.users.first
      expect(user[:id]).to eq('user123')
      expect(user[:email]).to eq('john@example.com')
      expect(user[:first_name]).to eq('John')
      expect(user[:last_name]).to eq('Doe')
      expect(user[:roles]).to eq(%w[APP_MANAGER DEVELOPER])
    end
  end

  describe '#create_user_invitation' do
    let(:invitation_response) do
      {
        data: {
          id: 'invite123',
          type: 'userInvitations',
          attributes: {
            email: 'invite@example.com',
            firstName: 'Invited',
            lastName: 'User',
            roles: ['DEVELOPER'],
            expirationDate: '2025-02-06T00:00:00Z'
          }
        }
      }
    end

    before do
      stub_api_post('/userInvitations', response_body: invitation_response)
    end

    it 'creates a user invitation' do
      result = client.create_user_invitation(
        email: 'invite@example.com',
        first_name: 'Invited',
        last_name: 'User',
        roles: ['DEVELOPER']
      )

      expect(result[:id]).to eq('invite123')
      expect(result[:email]).to eq('invite@example.com')
      expect(result[:roles]).to eq(['DEVELOPER'])
    end
  end

  describe '#territories' do
    let(:territories_response) do
      {
        data: [
          { id: 'USA', type: 'territories', attributes: { currency: 'USD' } },
          { id: 'GBR', type: 'territories', attributes: { currency: 'GBP' } },
          { id: 'JPN', type: 'territories', attributes: { currency: 'JPY' } }
        ]
      }
    end

    before do
      stub_api_get('/territories?limit=200', response_body: territories_response)
    end

    it 'returns a list of territories' do
      territories = client.territories
      expect(territories).to be_an(Array)
      expect(territories.length).to eq(3)
    end

    it 'returns territory with correct attributes' do
      territory = client.territories.first
      expect(territory[:id]).to eq('USA')
      expect(territory[:currency]).to eq('USD')
    end
  end

  describe 'error handling' do
    context 'when API returns an error' do
      before do
        stub_api_get(
          '/apps',
          response_body: sample_error_response(
            title: 'Authentication Error',
            detail: 'Invalid API key'
          ),
          status: 401
        )
      end

      it 'raises ApiError with error details' do
        expect { client.apps }.to raise_error(
          AppStoreConnect::ApiError,
          /Unauthorized/
        )
      end
    end
  end

  describe '#generate_token' do
    it 'generates a valid JWT token' do
      token = client.send(:generate_token)
      expect(token).to be_a(String)
      expect(token.split('.').length).to eq(3) # JWT has 3 parts
    end

    it 'includes correct claims' do
      token = client.send(:generate_token)
      payload = JWT.decode(token, nil, false).first

      expect(payload['iss']).to eq('TEST_ISSUER_ID')
      expect(payload['aud']).to eq('appstoreconnect-v1')
      expect(payload['exp']).to be > Time.now.to_i
    end
  end

  describe '#app_screenshot_sets' do
    let(:screenshot_sets_response) do
      {
        data: [
          {
            id: 'set123',
            type: 'appScreenshotSets',
            attributes: {
              screenshotDisplayType: 'APP_IPHONE_67'
            }
          },
          {
            id: 'set456',
            type: 'appScreenshotSets',
            attributes: {
              screenshotDisplayType: 'APP_IPAD_PRO_129'
            }
          }
        ]
      }
    end

    before do
      stub_api_get(
        '/appStoreVersionLocalizations/loc123/appScreenshotSets',
        response_body: screenshot_sets_response
      )
    end

    it 'returns a list of screenshot sets' do
      sets = client.app_screenshot_sets(localization_id: 'loc123')
      expect(sets).to be_an(Array)
      expect(sets.length).to eq(2)
    end

    it 'returns screenshot set with correct attributes' do
      set = client.app_screenshot_sets(localization_id: 'loc123').first
      expect(set[:id]).to eq('set123')
      expect(set[:screenshot_display_type]).to eq('APP_IPHONE_67')
    end
  end

  describe '#app_screenshots' do
    let(:screenshots_response) do
      {
        data: [
          {
            id: 'ss123',
            type: 'appScreenshots',
            attributes: {
              fileName: 'screenshot1.png',
              fileSize: 123_456,
              assetDeliveryState: { state: 'COMPLETE' },
              sourceFileChecksum: 'abc123'
            }
          }
        ]
      }
    end

    before do
      stub_api_get(
        '/appScreenshotSets/set123/appScreenshots',
        response_body: screenshots_response
      )
    end

    it 'returns a list of screenshots' do
      screenshots = client.app_screenshots(screenshot_set_id: 'set123')
      expect(screenshots).to be_an(Array)
      expect(screenshots.length).to eq(1)
    end

    it 'returns screenshot with correct attributes' do
      screenshot = client.app_screenshots(screenshot_set_id: 'set123').first
      expect(screenshot[:id]).to eq('ss123')
      expect(screenshot[:file_name]).to eq('screenshot1.png')
      expect(screenshot[:upload_state]).to eq('COMPLETE')
    end
  end

  describe '#delete_app_screenshot' do
    before do
      stub_api_delete('/appScreenshots/ss123')
    end

    it 'deletes the screenshot' do
      expect { client.delete_app_screenshot(screenshot_id: 'ss123') }.not_to raise_error
    end
  end
end
