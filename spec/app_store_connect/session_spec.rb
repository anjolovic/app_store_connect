# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AppStoreConnect::Session do
  subject(:session) { described_class.new }

  around do |example|
    original_session = ENV['FASTLANE_SESSION']
    ENV.delete('FASTLANE_SESSION')
    example.run
    ENV['FASTLANE_SESSION'] = original_session if original_session
  end

  describe '#initialize' do
    it 'creates an empty cookies hash' do
      expect(session.cookies).to eq({})
    end
  end

  describe '#valid?' do
    context 'when no cookies are present' do
      it 'returns false' do
        expect(session.valid?).to be false
      end
    end

    context 'when myacinfo cookie is present' do
      before do
        ENV['FASTLANE_SESSION'] = 'myacinfo=test_value; other=value'
      end

      it 'returns true' do
        expect(session.valid?).to be true
      end
    end

    context 'when cookies are present but myacinfo is missing' do
      before do
        ENV['FASTLANE_SESSION'] = 'other=value; session=abc'
      end

      it 'returns false' do
        expect(session.valid?).to be false
      end
    end
  end

  describe '#cookie_header' do
    before do
      ENV['FASTLANE_SESSION'] = 'myacinfo=test123; itctx=abc456'
    end

    it 'returns cookies formatted as header string' do
      header = session.cookie_header
      expect(header).to include('myacinfo=test123')
      expect(header).to include('itctx=abc456')
      expect(header).to include('; ')
    end
  end

  describe '#load_session' do
    context 'with simple cookie string' do
      before do
        ENV['FASTLANE_SESSION'] = 'myacinfo=value1; DES123=value2'
      end

      it 'parses cookies correctly' do
        expect(session.cookies['myacinfo']).to eq('value1')
        expect(session.cookies['DES123']).to eq('value2')
      end
    end

    context 'with YAML array format' do
      before do
        ENV['FASTLANE_SESSION'] = "---\n- myacinfo=value1\n- itctx=value2"
      end

      it 'parses YAML cookie format' do
        expect(session.cookies['myacinfo']).to eq('value1')
        expect(session.cookies['itctx']).to eq('value2')
      end
    end

    context 'when cookie attributes are present' do
      before do
        ENV['FASTLANE_SESSION'] = 'myacinfo=value; path=/; domain=.apple.com; secure'
      end

      it 'ignores cookie attributes' do
        expect(session.cookies).to eq({ 'myacinfo' => 'value' })
        expect(session.cookies).not_to have_key('path')
        expect(session.cookies).not_to have_key('domain')
        expect(session.cookies).not_to have_key('secure')
      end
    end
  end

  describe '#clear_session' do
    before do
      ENV['FASTLANE_SESSION'] = 'myacinfo=test'
    end

    it 'clears the cookies hash' do
      expect(session.cookies).not_to be_empty
      session.clear_session
      expect(session.cookies).to eq({})
    end
  end
end
