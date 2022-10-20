require 'nginx_omniauth_adapter'
require 'omniauth-github'
require 'open-uri'
require 'rack/ssl-enforcer'

if ENV['RACK_ENV'] != 'development'
  use Rack::SslEnforcer
end

use Rack::Session::Cookie,
  key: ENV['RACK_SESSION_KEY'],
  secret: ENV['RACK_SESSION_SECRET'],
  secure: true,
  expire_after: 60 * 60 * 24 * 30

use OmniAuth::Builder do
  provider :github, ENV['GITHUB_KEY'], ENV['GITHUB_SECRET'], scope: 'read:org'
end

GH_TEAMS = %w(
  dark-kuins-net/all
)

run NginxOmniauthAdapter.app(
  providers: %i(github),
  key: ENV['RACK_SESSION_KEY'],
  secret: ENV['RACK_SESSION_SECRET'], # `openssl rand -base64 32`
  host: 'https://auth.dark-kuins.net',
  allowed_app_callback_url: %r(\Ahttps://[^/]+\.(dark-kuins\.net|nna774\.net)/),
  app_refresh_interval: 60 * 60 * 24 * 2,
  adapter_refresh_interval: 60 * 60 * 24 * 7,
  policy_proc: proc {
    (current_user_data[:gh_teams] || []).any? { |team| GH_TEAMS.include?(team) }
  },
  on_login_proc: proc {
    auth = env['omniauth.auth']
    if GH_TEAMS
      api_host = 'https://api.github.com'
      current_user_data[:gh_teams] = open("#{api_host}/user/teams", 'Authorization' => "token #{auth['credentials']['token']}") { |io|
        JSON.parse(io.read).map {|_| "#{_['organization']['login']}/#{_['slug']}" }.select { |team| GH_TEAMS.include?(team) }
      }
    end
    true
  },
)
