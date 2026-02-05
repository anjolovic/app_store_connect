# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe AppStoreConnect::CLI do
  # Create a test private key for the client
  let(:private_key) { OpenSSL::PKey::EC.generate('prime256v1') }

  let(:key_file) do
    file = Tempfile.new(['test_key', '.p8'])
    file.write(private_key.to_pem)
    file.rewind
    file
  end

  before do
    AppStoreConnect.configure do |config|
      config.key_id = 'TEST_KEY_ID'
      config.issuer_id = 'TEST_ISSUER_ID'
      config.private_key_path = key_file.path
      config.app_id = '123456789'
      config.bundle_id = 'com.example.app'
    end
  end

  after do
    key_file.close
    key_file.unlink
  end

  describe '#initialize' do
    it 'sets the command from args' do
      cli = described_class.new(['status'])
      expect(cli.instance_variable_get(:@command)).to eq('status')
    end

    it 'sets options from remaining args' do
      cli = described_class.new(['status', '--verbose', '--json'])
      expect(cli.instance_variable_get(:@options)).to eq([])
      expect(cli.global_options[:verbose]).to eq(true)
      expect(cli.global_options[:json]).to eq(true)
    end

    it 'defaults to status command when no args' do
      cli = described_class.new([])
      expect(cli.instance_variable_get(:@command)).to eq('status')
    end
  end

  describe '#run' do
    context 'with unknown command' do
      it 'exits with error' do
        cli = described_class.new(['unknown_command'])

        expect { cli.run }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end

      it 'outputs error message' do
        cli = described_class.new(['unknown_command'])

        expect { cli.run }.to output(/Unknown command: unknown_command/).to_stdout.and raise_error(SystemExit)
      end
    end

    context 'with help command' do
      it 'outputs help text' do
        cli = described_class.new(['help'])

        expect { cli.run }.to output(/App Store Connect CLI/).to_stdout
      end

      it 'lists available commands' do
        cli = described_class.new(['help'])

        expect { cli.run }.to output(/status.*review.*builds/m).to_stdout
      end
    end

    context 'with apps command' do
      before do
        stub_api_get('/apps', response_body: sample_apps_response)
      end

      it 'outputs apps list' do
        cli = described_class.new(['apps'])

        expect { cli.run }.to output(/Test App/).to_stdout
      end
    end

    context 'with testers command' do
      before do
        stub_api_get(
          '/betaTesters?filter[apps]=123456789&limit=100',
          response_body: sample_beta_testers_response
        )
      end

      it 'outputs beta testers list' do
        cli = described_class.new(['testers'])

        expect { cli.run }.to output(/tester@example.com/).to_stdout
      end
    end

    context 'with tester-groups command' do
      before do
        stub_api_get(
          '/apps/123456789/betaGroups',
          response_body: sample_beta_groups_response
        )
      end

      it 'outputs beta groups list' do
        cli = described_class.new(['tester-groups'])

        expect { cli.run }.to output(/External Testers/).to_stdout
      end
    end

    context 'with users command' do
      before do
        stub_api_get('/users?limit=100', response_body: sample_users_response)
      end

      it 'outputs users list' do
        cli = described_class.new(['users'])

        expect { cli.run }.to output(/john@example.com/).to_stdout
      end
    end

    context 'with territories command' do
      let(:territories_response) do
        {
          data: [
            { id: 'USA', type: 'territories', attributes: { currency: 'USD' } },
            { id: 'GBR', type: 'territories', attributes: { currency: 'GBP' } }
          ]
        }
      end

      before do
        stub_api_get('/territories?limit=200', response_body: territories_response)
      end

      it 'outputs territories list' do
        cli = described_class.new(['territories'])

        expect { cli.run }.to output(/USA/).to_stdout
      end
    end

    context 'with categories command' do
      let(:categories_response) do
        {
          data: [
            {
              id: 'GAMES',
              type: 'appCategories',
              attributes: { platforms: ['IOS'] }
            },
            {
              id: 'UTILITIES',
              type: 'appCategories',
              attributes: { platforms: %w[IOS MAC_OS] }
            }
          ]
        }
      end

      before do
        stub_api_get('/appCategories?filter[platforms]=IOS', response_body: categories_response)
      end

      it 'outputs categories list' do
        cli = described_class.new(['categories'])

        expect { cli.run }.to output(/GAMES|UTILITIES/).to_stdout
      end
    end

    context 'with create-sub command' do
      it 'errors when missing required args' do
        cli = described_class.new(['create-sub'])

        expect { cli.run }.to output(/Usage: asc create-sub/).to_stdout.and raise_error(SystemExit)
      end

      it 'errors when subscription already exists' do
        stub_api_get(
          '/apps/123456789/subscriptionGroups',
          response_body: {
            data: [
              { id: 'group1', type: 'subscriptionGroups', attributes: { referenceName: 'Main Plans' } }
            ]
          }
        )
        stub_api_get(
          '/subscriptionGroups/group1/subscriptions',
          response_body: {
            data: [
              {
                id: 'sub1',
                type: 'subscriptions',
                attributes: {
                  productId: 'com.example.app.plan.monthly',
                  name: 'Monthly Plan',
                  state: 'READY_TO_SUBMIT'
                }
              }
            ]
          }
        )
        stub_api_get('/apps/123456789/inAppPurchasesV2', response_body: { data: [] })

        cli = described_class.new([
                                   'create-sub',
                                   'com.example.app.plan.monthly',
                                   'Monthly Plan',
                                   '1m',
                                   '--group-id',
                                   'group1'
                                 ])

        expect { cli.run }.to output(/Subscription already exists/).to_stdout.and raise_error(SystemExit)
      end

      it 'errors when --json is used without --yes' do
        cli = described_class.new([
                                   'create-sub',
                                   'com.example.app.plan.monthly',
                                   'Monthly Plan',
                                   '1m',
                                   '--json'
                                 ])

        expect { cli.run }.to output(/--json requires --yes/).to_stdout.and raise_error(SystemExit)
      end

      it 'errors when product id is already used by an IAP' do
        stub_api_get('/apps/123456789/subscriptionGroups', response_body: { data: [] })
        stub_api_get(
          '/apps/123456789/inAppPurchasesV2',
          response_body: {
            data: [
              {
                id: 'iap1',
                type: 'inAppPurchases',
                attributes: {
                  productId: 'com.example.app.plan.monthly',
                  name: 'Monthly Coins',
                  state: 'READY_TO_SUBMIT',
                  inAppPurchaseType: 'CONSUMABLE'
                }
              }
            ]
          }
        )

        cli = described_class.new([
                                   'create-sub',
                                   'com.example.app.plan.monthly',
                                   'Monthly Plan',
                                   '1m',
                                   '--group',
                                   'Main Plans',
                                   '--create-group'
                                 ])

        expect { cli.run }.to output(/Product ID already used by an in-app purchase/).to_stdout.and raise_error(SystemExit)
      end

      it 'errors when multiple groups exist but none specified' do
        stub_api_get(
          '/apps/123456789/subscriptionGroups',
          response_body: {
            data: [
              { id: 'group1', type: 'subscriptionGroups', attributes: { referenceName: 'Main Plans' } },
              { id: 'group2', type: 'subscriptionGroups', attributes: { referenceName: 'Legacy Plans' } }
            ]
          }
        )
        stub_api_get('/subscriptionGroups/group1/subscriptions', response_body: { data: [] })
        stub_api_get('/subscriptionGroups/group2/subscriptions', response_body: { data: [] })
        stub_api_get('/apps/123456789/inAppPurchasesV2', response_body: { data: [] })

        cli = described_class.new(['create-sub', 'com.example.app.plan.monthly', 'Monthly Plan', '1m'])

        expect { cli.run }.to output(/Multiple subscription groups found/).to_stdout.and raise_error(SystemExit)
      end

      it 'supports dry run without creating resources' do
        stub_api_get('/apps/123456789/subscriptionGroups', response_body: { data: [] })
        stub_api_get('/apps/123456789/inAppPurchasesV2', response_body: { data: [] })

        cli = described_class.new([
                                   'create-sub',
                                   'com.example.app.plan.monthly',
                                   'Monthly Plan',
                                   '1m',
                                   '--group',
                                   'Main Plans',
                                   '--create-group',
                                   '--dry-run'
                                 ])

        expect { cli.run }.to output(/Dry run/).to_stdout
        expect(WebMock).not_to have_requested(:post, /subscriptionGroups/)
        expect(WebMock).not_to have_requested(:post, /subscriptions/)
      end

      it 'creates a subscription with pricing, intro offer, and localizations' do
        stub_api_get('/apps/123456789/subscriptionGroups', response_body: { data: [] })
        stub_api_get('/apps/123456789/inAppPurchasesV2', response_body: { data: [] })

        stub_api_post(
          '/subscriptionGroups',
          response_body: {
            data: {
              id: 'group_new',
              type: 'subscriptionGroups',
              attributes: { referenceName: 'Main Plans' }
            }
          }
        )

        stub_api_post(
          '/subscriptions',
          response_body: {
            data: {
              id: 'sub_new',
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
        )

        stub_api_post(
          '/subscriptionLocalizations',
          response_body: {
            data: {
              id: 'loc1',
              type: 'subscriptionLocalizations',
              attributes: {
                locale: 'en-US',
                name: 'Monthly Plan',
                description: 'Access premium features'
              }
            }
          }
        )

        stub_api_get(
          '/subscriptions/sub_new/pricePoints?filter[territory]=USA&include=territory&limit=2000',
          response_body: {
            data: [
              { id: 'price_point_1', type: 'subscriptionPricePoints' }
            ]
          }
        )

        stub_api_post(
          '/subscriptionPrices',
          response_body: {
            data: {
              id: 'price_1',
              type: 'subscriptionPrices',
              attributes: { startDate: '2026-03-01' },
              relationships: {
                subscriptionPricePoint: {
                  data: { id: 'price_point_1', type: 'subscriptionPricePoints' }
                }
              }
            }
          }
        )

        stub_api_post(
          '/subscriptionIntroductoryOffers',
          response_body: {
            data: {
              id: 'intro_1',
              type: 'subscriptionIntroductoryOffers',
              attributes: { offerMode: 'FREE_TRIAL', duration: 'ONE_WEEK' },
              relationships: {
                subscriptionPricePoint: {
                  data: { id: 'intro_price_1', type: 'subscriptionPricePoints' }
                }
              }
            }
          }
        )

        file = Tempfile.new(['localizations', '.yml'])
        begin
          file.write(<<~YAML)
            - locale: fr-FR
              name: Forfait mensuel
              description: Acces premium
          YAML
          file.rewind

          cli = described_class.new([
                                     'create-sub',
                                     'com.example.app.plan.monthly',
                                     'Monthly Plan',
                                     '1m',
                                     '--group',
                                     'Main Plans',
                                     '--create-group',
                                     '--group-level',
                                     '1',
                                     '--locale',
                                     'en-US',
                                     '--display-name',
                                     'Monthly Plan',
                                     '--description',
                                     'Access premium features',
                                     '--localizations-file',
                                     file.path,
                                     '--add-localization',
                                     'es-ES:Plan mensual:Acceso premium',
                                     '--price-point',
                                     'price_point_1',
                                     '--price-territory',
                                     'USA',
                                     '--price-start-date',
                                     '2026-03-01',
                                     '--intro-offer',
                                     'FREE_TRIAL',
                                     '--intro-duration',
                                     '1w',
                                     '--intro-price-point',
                                     'intro_price_1',
                                     '--yes'
                                   ])

          expect { cli.run }.to output(/Subscription created!/).to_stdout
        ensure
          file.close
          file.unlink
        end
      end
    end

    context 'with fix-sub-metadata command' do
      it 'errors when missing product id' do
        cli = described_class.new(['fix-sub-metadata'])

        expect { cli.run }.to output(/Usage: asc fix-sub-metadata/).to_stdout.and raise_error(SystemExit)
      end

      it 'updates localization and price for an existing subscription' do
        stub_api_get(
          '/apps/123456789/subscriptionGroups',
          response_body: {
            data: [
              { id: 'group1', type: 'subscriptionGroups', attributes: { referenceName: 'Plans' } }
            ]
          }
        )
        stub_api_get(
          '/subscriptionGroups/group1/subscriptions',
          response_body: {
            data: [
              {
                id: 'sub1',
                type: 'subscriptions',
                attributes: {
                  productId: 'com.example.app.plan.monthly',
                  name: 'Monthly Plan',
                  state: 'MISSING_METADATA'
                }
              }
            ]
          }
        )
        stub_api_get(
          '/subscriptions/sub1/subscriptionLocalizations',
          response_body: { data: [] }
        )
        stub_api_post(
          '/subscriptionLocalizations',
          response_body: {
            data: {
              id: 'loc1',
              type: 'subscriptionLocalizations',
              attributes: {
                locale: 'en-US',
                name: 'Monthly Plan',
                description: 'Access premium features'
              }
            }
          }
        )
        stub_api_get(
          '/subscriptions/sub1/pricePoints?filter[territory]=USA&include=territory&limit=2000',
          response_body: { data: [{ id: 'price_point_1', type: 'subscriptionPricePoints' }] }
        )
        stub_api_post(
          '/subscriptionPrices',
          response_body: {
            data: {
              id: 'price_1',
              type: 'subscriptionPrices',
              attributes: { startDate: '2026-03-01' },
              relationships: {
                subscriptionPricePoint: {
                  data: { id: 'price_point_1', type: 'subscriptionPricePoints' }
                }
              }
            }
          }
        )

        cli = described_class.new([
                                   'fix-sub-metadata',
                                   'com.example.app.plan.monthly',
                                   '--display-name',
                                   'Monthly Plan',
                                   '--description',
                                   'Access premium features',
                                   '--price-point',
                                   'price_point_1',
                                   '--price-territory',
                                   'USA',
                                   '--price-start-date',
                                   '2026-03-01',
                                   '--yes'
                                 ])

        expect { cli.run }.to output(/Metadata updated!/).to_stdout
      end
    end

    context 'with subscription management commands' do
      it 'shows subscription availability when none configured' do
        stub_subscription(product_id: 'com.example.app.plan.monthly', sub_id: 'sub1')
        stub_api_get(
          '/subscriptions/sub1/subscriptionAvailability?include=availableTerritories',
          response_body: sample_error_response(title: 'Not Found', detail: 'Availability not found'),
          status: 404
        )

        cli = described_class.new(['sub-availability', 'com.example.app.plan.monthly'])

        expect { cli.run }.to output(/No availability configured/).to_stdout
      end

      it 'sets subscription availability for territories' do
        stub_subscription(product_id: 'com.example.app.plan.monthly', sub_id: 'sub1')
        stub_api_get(
          '/subscriptions/sub1/subscriptionAvailability?include=availableTerritories',
          response_body: sample_error_response(title: 'Not Found', detail: 'Availability not found'),
          status: 404
        )
        stub_api_post(
          '/subscriptionAvailabilities',
          response_body: { data: { id: 'avail1', type: 'subscriptionAvailabilities' } }
        )

        cli = described_class.new([
                                   'set-sub-availability',
                                   'com.example.app.plan.monthly',
                                   'USA',
                                   '--available-in-new-territories',
                                   'true',
                                   '--yes'
                                 ])

        expect { cli.run }.to output(/Availability updated!/).to_stdout
      end

      it 'lists subscription price points' do
        stub_subscription(product_id: 'com.example.app.plan.monthly', sub_id: 'sub1')
        stub_api_get(
          '/subscriptions/sub1/pricePoints?filter[territory]=USA&include=territory&limit=200',
          response_body: {
            data: [
              {
                id: 'price_point_1',
                type: 'subscriptionPricePoints',
                attributes: { customerPrice: '4.99', proceeds: '3.50' }
              }
            ]
          }
        )

        cli = described_class.new(['sub-price-points', 'com.example.app.plan.monthly', 'USA'])

        expect { cli.run }.to output(/price_point_1/).to_stdout
      end

      it 'warns when --after is provided' do
        stub_subscription(product_id: 'com.example.app.plan.monthly', sub_id: 'sub1')

        stub_api_get(
          '/subscriptions/sub1/pricePoints?filter[territory]=USA&include=territory&limit=1',
          response_body: {
            data: [
              {
                id: 'price_point_low',
                type: 'subscriptionPricePoints',
                attributes: { customerPrice: '4.99', proceeds: '3.50' }
              }
            ],
            links: {
              next: 'https://api.appstoreconnect.apple.com/v1/subscriptions/sub1/pricePoints?filter[territory]=USA&include=territory&limit=1&page[cursor]=NEXT_CURSOR'
            }
          }
        )

        cli = described_class.new([
                                   'sub-price-points',
                                   'com.example.app.plan.monthly',
                                   'USA',
                                   '--limit',
                                   '1',
                                   '--after',
                                   'NEXT_CURSOR'
                                 ])

        expect { cli.run }.to output(/--after is not supported/).to_stdout
      end

      it 'filters price points by customer price' do
        stub_subscription(product_id: 'com.example.app.plan.monthly', sub_id: 'sub1')
        stub_api_get(
          '/subscriptions/sub1/pricePoints?filter[territory]=USA&include=territory&limit=2000',
          response_body: {
            data: [
              { id: 'price_point_59', type: 'subscriptionPricePoints', attributes: { customerPrice: '59.00' } },
              { id: 'price_point_599', type: 'subscriptionPricePoints', attributes: { customerPrice: '599.00' } }
            ]
          }
        )

        cli = described_class.new([
                                   'sub-price-points',
                                   'com.example.app.plan.monthly',
                                   'USA',
                                   '--search-price',
                                   '599'
                                 ])

        expect { cli.run }.to output(/price_point_599/).to_stdout
      end

      it 'adds a subscription price' do
        stub_subscription(product_id: 'com.example.app.plan.monthly', sub_id: 'sub1')
        stub_api_post(
          '/subscriptionPrices',
          response_body: {
            data: {
              id: 'price_1',
              type: 'subscriptionPrices',
              attributes: { startDate: '2026-03-01' },
              relationships: {
                subscriptionPricePoint: {
                  data: { id: 'price_point_1', type: 'subscriptionPricePoints' }
                }
              }
            }
          }
        )

        cli = described_class.new([
                                   'add-sub-price',
                                   'com.example.app.plan.monthly',
                                   'price_point_1',
                                   '--start-date',
                                   '2026-03-01'
                                 ])

        expect { cli.run }.to output(/Subscription price added!/).to_stdout
      end

      it 'lists tax categories' do
        stub_api_get(
          '/taxCategories?limit=200',
          response_body: {
            data: [
              { id: 'TAX001', type: 'taxCategories', attributes: { name: 'Standard' } }
            ]
          }
        )

        cli = described_class.new(['tax-categories'])

        expect { cli.run }.to output(/TAX001/).to_stdout
      end

      it 'submits a subscription group for review' do
        stub_api_get(
          '/apps/123456789/subscriptionGroups',
          response_body: {
            data: [
              { id: 'group1', type: 'subscriptionGroups', attributes: { referenceName: 'Plans' } }
            ]
          }
        )
        stub_api_post(
          '/subscriptionGroupSubmissions',
          response_body: {
            data: {
              id: 'sgs1',
              type: 'subscriptionGroupSubmissions',
              attributes: { state: 'WAITING_FOR_REVIEW' }
            }
          }
        )

        cli = described_class.new(['submit-sub-group', 'Plans', '--yes'])

        expect { cli.run }.to output(/Subscription group submitted!/).to_stdout
      end

      it 'outputs dry-run json for sub-ensure-assets with only missing subscriptions' do
        review_file = Tempfile.new(['review', '.png'])
        image_file = Tempfile.new(['image', '.png'])
        review_file.binmode
        image_file.binmode
        review_file.write('fakepng')
        image_file.write('fakepng1024')
        review_file.rewind
        image_file.rewind

        stub_api_get(
          '/apps/123456789/subscriptionGroups',
          response_body: {
            data: [
              { id: 'group1', type: 'subscriptionGroups', attributes: { referenceName: 'Main Plans' } }
            ]
          }
        )
        stub_api_get(
          '/subscriptionGroups/group1/subscriptions',
          response_body: {
            data: [
              { id: 'sub1', type: 'subscriptions', attributes: { productId: 'com.example.app.plan.missing', name: 'Missing', state: 'MISSING_METADATA' } },
              { id: 'sub2', type: 'subscriptions', attributes: { productId: 'com.example.app.plan.ok', name: 'OK', state: 'READY_TO_SUBMIT' } }
            ]
          }
        )

        stub_api_get('/subscriptions/sub1/appStoreReviewScreenshot', response_body: sample_error_response(title: 'Not found'), status: 404)
        stub_api_get('/subscriptions/sub1/images', response_body: { data: [] })

        stub_api_get(
          '/subscriptions/sub2/appStoreReviewScreenshot',
          response_body: { data: { id: 'shot_ok', type: 'subscriptionAppStoreReviewScreenshots', attributes: { fileName: 'ok.png', fileSize: 123, assetDeliveryState: { state: 'COMPLETE' } } } }
        )
        stub_api_get(
          '/subscriptions/sub2/images',
          response_body: { data: [{ id: 'img_ok', type: 'subscriptionImages', attributes: { fileName: 'ok.png', fileSize: 123, assetDeliveryState: { state: 'COMPLETE' } } }] }
        )

        cli = described_class.new([
                                   'sub-ensure-assets',
                                   '--review-screenshot', review_file.path,
                                   '--image-file', image_file.path,
                                   '--only-missing',
                                   '--dry-run',
                                   '--json'
                                 ])

        expect { cli.run }.to output(/"product_id": "com\.example\.app\.plan\.missing"/).to_stdout
      ensure
        review_file.close
        review_file.unlink
        image_file.close
        image_file.unlink
      end

      it 'uploads missing assets for sub-ensure-assets and waits for COMPLETE' do
        review_file = Tempfile.new(['review', '.png'])
        image_file = Tempfile.new(['image', '.png'])
        review_file.binmode
        image_file.binmode
        review_file.write('fakepng')
        image_file.write('fakepng1024')
        review_file.rewind
        image_file.rewind

        stub_api_get(
          '/apps/123456789/subscriptionGroups',
          response_body: {
            data: [
              { id: 'group1', type: 'subscriptionGroups', attributes: { referenceName: 'Main Plans' } }
            ]
          }
        )
        stub_api_get(
          '/subscriptionGroups/group1/subscriptions',
          response_body: {
            data: [
              { id: 'sub1', type: 'subscriptions', attributes: { productId: 'com.example.app.plan.missing', name: 'Missing', state: 'MISSING_METADATA' } }
            ]
          }
        )

        stub_api_get('/subscriptions/sub1/appStoreReviewScreenshot', response_body: sample_error_response(title: 'Not found'), status: 404)
        stub_api_get('/subscriptions/sub1/images', response_body: { data: [] })

        stub_api_post(
          '/subscriptionAppStoreReviewScreenshots',
          response_body: {
            data: {
              id: 'shot1',
              type: 'subscriptionAppStoreReviewScreenshots',
              attributes: {
                uploadOperations: [
                  {
                    url: 'https://example-upload.test/review-shot1',
                    offset: 0,
                    length: 7,
                    requestHeaders: [{ name: 'Content-Type', value: 'image/png' }]
                  }
                ]
              }
            }
          }
        )
        stub_request(:put, 'https://example-upload.test/review-shot1').to_return(status: 200, body: '')
        stub_api_patch('/subscriptionAppStoreReviewScreenshots/shot1', response_body: { data: { id: 'shot1', type: 'subscriptionAppStoreReviewScreenshots' } })

        first = stub_api_get(
          '/subscriptionAppStoreReviewScreenshots/shot1',
          response_body: { data: { id: 'shot1', type: 'subscriptionAppStoreReviewScreenshots', attributes: { assetDeliveryState: { state: 'UPLOADED' } } } }
        )
        first.to_return(
          status: 200,
          body: { data: { id: 'shot1', type: 'subscriptionAppStoreReviewScreenshots', attributes: { assetDeliveryState: { state: 'COMPLETE' } } } }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

        stub_api_post(
          '/subscriptionImages',
          response_body: {
            data: {
              id: 'img1',
              type: 'subscriptionImages',
              attributes: {
                uploadOperations: [
                  {
                    url: 'https://example-upload.test/image-img1',
                    offset: 0,
                    length: 11,
                    requestHeaders: [{ name: 'Content-Type', value: 'image/png' }]
                  }
                ]
              }
            }
          }
        )
        stub_request(:put, 'https://example-upload.test/image-img1').to_return(status: 200, body: '')
        stub_api_patch('/subscriptionImages/img1', response_body: { data: { id: 'img1', type: 'subscriptionImages' } })

        second = stub_api_get(
          '/subscriptionImages/img1',
          response_body: { data: { id: 'img1', type: 'subscriptionImages', attributes: { assetDeliveryState: { state: 'UPLOADED' } } } }
        )
        second.to_return(
          status: 200,
          body: { data: { id: 'img1', type: 'subscriptionImages', attributes: { assetDeliveryState: { state: 'COMPLETE' } } } }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

        cli = described_class.new([
                                   'sub-ensure-assets',
                                   '--review-screenshot', review_file.path,
                                   '--image-file', image_file.path,
                                   '--yes',
                                   '--wait',
                                   '--timeout', '2',
                                   '--interval', '1',
                                   '--json'
                                 ])

        expect { cli.run }.to output(/"upload_review_screenshot"/).to_stdout
        expect(WebMock).to have_requested(:post, /subscriptionAppStoreReviewScreenshots/)
        expect(WebMock).to have_requested(:post, /subscriptionImages/)
      ensure
        review_file.close
        review_file.unlink
        image_file.close
        image_file.unlink
      end
    end

    context 'when configuration is missing' do
      before do
        AppStoreConnect.reset_configuration!
      end

      it 'exits with error' do
        cli = described_class.new(['apps'])

        expect { cli.run }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end

      it 'outputs configuration error message' do
        cli = described_class.new(['apps'])

        expect { cli.run }.to output(/Configuration Error/).to_stdout.and raise_error(SystemExit)
      end
    end

    context 'when API returns an error' do
      before do
        stub_api_get(
          '/apps',
          response_body: sample_error_response(
            title: 'Not Found',
            detail: 'App not found'
          ),
          status: 404
        )
      end

      it 'exits with error' do
        cli = described_class.new(['apps'])

        expect { cli.run }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end

      it 'outputs API error message' do
        cli = described_class.new(['apps'])

        expect { cli.run }.to output(/API Error/).to_stdout.and raise_error(SystemExit)
      end
    end
  end

  describe 'COMMANDS constant' do
    it 'includes all expected commands' do
      expected_commands = %w[
        status review builds apps help testers users territories categories
        create-sub fix-sub-metadata
        sub-details sub-metadata-status sub-ensure-assets
        sub-availability set-sub-availability sub-price-points sub-prices add-sub-price
        sub-image upload-sub-image delete-sub-image
        sub-review-screenshot upload-sub-review-screenshot delete-sub-review-screenshot
        set-sub-tax-category tax-categories sub-localizations update-sub-localization
        sub-intro-offers delete-sub-intro-offer
        sub-groups sub-group-submissions submit-sub-group sub-group-localizations
      ]

      expected_commands.each do |cmd|
        expect(described_class::COMMANDS).to include(cmd)
      end
    end
  end

  def with_stdin(input)
    original_stdin = $stdin
    $stdin = StringIO.new(input)
    yield
  ensure
    $stdin = original_stdin
  end

  def stub_subscription(product_id:, sub_id:, name: 'Monthly Plan')
    stub_api_get(
      '/apps/123456789/subscriptionGroups',
      response_body: {
        data: [
          { id: 'group1', type: 'subscriptionGroups', attributes: { referenceName: 'Plans' } }
        ]
      }
    )
    stub_api_get(
      '/subscriptionGroups/group1/subscriptions',
      response_body: {
        data: [
          {
            id: sub_id,
            type: 'subscriptions',
            attributes: {
              productId: product_id,
              name: name,
              state: 'READY_TO_SUBMIT'
            }
          }
        ]
      }
    )
  end
end
