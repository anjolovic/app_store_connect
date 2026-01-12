# frozen_string_literal: true

require_relative 'lib/app_store_connect/version'

Gem::Specification.new do |spec|
  spec.name          = 'app_store_connect'
  spec.version       = AppStoreConnect::VERSION
  spec.authors       = ['Alen Jolovic']
  spec.email         = ['alen@porchq.com']

  spec.summary       = 'Ruby client and CLI for App Store Connect API'
  spec.description   = "Ruby library and CLI for Apple's App Store Connect API. " \
                       'Manage app status, reviews, subscriptions, and respond to Apple Review requests.'
  spec.homepage      = 'https://github.com/anjolovic/app_store_connect'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.1'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = 'exe'
  spec.executables = ['asc']
  spec.require_paths = ['lib']

  spec.add_dependency 'jwt', '~> 2.7'

  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.12'
  spec.add_development_dependency 'rubocop', '~> 1.50'
  spec.add_development_dependency 'simplecov', '~> 0.22'
  spec.add_development_dependency 'webmock', '~> 3.19'
end
