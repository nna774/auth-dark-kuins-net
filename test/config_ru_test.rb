# frozen_string_literal: true

ENV['RACK_ENV'] = 'production'
ENV['GITHUB_KEY'] = 'test-key'
ENV['GITHUB_SECRET'] = 'test-secret'
ENV['RACK_SESSION_KEY'] = 'test_session'
ENV['RACK_SESSION_SECRET'] = ['x' * 32].pack('m0')

require 'minitest/autorun'
require 'rack/test'
require 'rack/builder'

CONFIG_RU_APP = Rack::Builder.parse_file(File.expand_path('../config.ru', __dir__)).then { _1.is_a?(Array) ? _1.first : _1 }
OmniAuth.config.logger = Logger.new(IO::NULL)

class ConfigRuTest < Minitest::Test
  include Rack::Test::Methods

  BACK_TO = 'https://grafana.dark-kuins.net/'
  CALLBACK = 'https://grafana.dark-kuins.net/_auth/callback'

  def app
    CONFIG_RU_APP
  end

  # セッションの cookie は secure なので、https で投げないと送り返されない。
  def get(path, ...)
    super(path.start_with?('/') ? "https://auth.dark-kuins.net#{path}" : path, ...)
  end

  def teardown
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:github] = nil
  end

  def start_auth
    get '/auth', back_to: BACK_TO, callback: CALLBACK
    assert_equal 'https://auth.dark-kuins.net/auth/github', last_response.location
    get '/auth/github'
  end

  def test_root
    get '/'
    assert_equal 'o-su!', last_response.body
  end

  def test_redirect_uri_ignores_forged_host
    get 'https://evil.example.com/auth/github'
    uri = URI(last_response.location)
    assert_equal 'github.com', uri.host
    assert_equal 'https://auth.dark-kuins.net/auth/github/callback', Rack::Utils.parse_query(uri.query)['redirect_uri']
  end

  def test_stale_callback_restarts_auth_once
    start_auth
    get '/auth/github/callback', state: 'stale', code: 'x'
    assert_equal '/auth/failure?message=csrf_detected&strategy=github', last_response.location

    get last_response.location
    assert_equal 'https://auth.dark-kuins.net/auth/github', last_response.location

    get '/auth/github/callback', state: 'stale', code: 'x'
    get last_response.location
    assert_equal 404, last_response.status
  end

  def test_stale_callback_without_back_to_does_not_restart
    get '/auth/github/callback', state: 'stale', code: 'x'
    assert_equal '/auth/failure?message=csrf_detected&strategy=github', last_response.location

    get last_response.location
    assert_equal 404, last_response.status
  end

  def log_in_as(uid)
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(provider: 'github', uid: uid)
    start_auth
    get '/auth/github/callback'
    app_callback = URI(last_response.location)
    assert_equal CALLBACK, "https://#{app_callback.host}#{app_callback.path}"

    get "/callback?#{app_callback.query}"
    assert_equal BACK_TO, last_response.location
    get '/test'
  end

  def test_allowed_uid_passes
    log_in_as('691828')
    assert_equal 200, last_response.status
    assert_equal '691828', last_response.headers['x-ngx-omniauth-user']
  end

  def test_other_uid_is_forbidden
    log_in_as('1')
    assert_equal 403, last_response.status
  end
end
