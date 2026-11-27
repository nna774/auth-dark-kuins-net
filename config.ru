require 'nginx_omniauth_adapter'
require 'omniauth-github'
require 'rack/ssl-enforcer'

if ENV['RACK_ENV'] != 'development'
  use Rack::SslEnforcer
end

# nginx_omniauth_adapter は /auth/:provider へ GET でリダイレクトしてくる。
# omniauth 2 は既定で POST だけを許すので、GET を許可する。
OmniAuth.config.allowed_request_methods = %i(get)
OmniAuth.config.silence_get_warning = true
# 既定では callback の URL を Host ヘッダから組むので、偽の Host で別のホストに向けられないよう固定する。
OmniAuth.config.full_host = 'https://auth.dark-kuins.net'

# RACK_SESSION_KEY は cookie の名前になる。rack は cookie 名をエスケープして返すのに、
# 読み戻す時は名前をアンエスケープしないので、+ / = などを含むとセッションが読めなくなる。
SESSION_KEY = ENV['RACK_SESSION_KEY'].to_s.delete('^A-Za-z0-9_-')

use Rack::Session::Cookie,
  key: SESSION_KEY,
  secret: ENV['RACK_SESSION_SECRET'],
  secure: true,
  expire_after: 60 * 60 * 24 * 30

use OmniAuth::Builder do
  # スコープは要求しない (公開情報の uid だけ使う)。org やチームは読まない。
  provider :github, ENV['GITHUB_KEY'], ENV['GITHUB_SECRET'], scope: ''
end

# 許可する GitHub のユーザー ID (数値。ログイン名は変更されて他人に渡りうるので使わない)。
# 691828: nna774
GH_UIDS = %w(691828)

app = NginxOmniauthAdapter.app(
  providers: %i(github),
  key: SESSION_KEY,
  secret: ENV['RACK_SESSION_SECRET'], # `openssl rand -base64 32`
  host: 'https://auth.dark-kuins.net',
  allowed_app_callback_url: %r(\Ahttps://[^/]+\.(dark-kuins\.net|nna774\.net)/),
  app_refresh_interval: 60 * 60 * 24 * 2,
  adapter_refresh_interval: 60 * 60 * 24 * 7,
  policy_proc: proc {
    GH_UIDS.include?(current_user_data[:gh_uid])
  },
  on_login_proc: proc {
    current_user_data[:gh_uid] = env['omniauth.auth']['uid'].to_s
    true
  },
)

# 復元されたタブなどで古い callback の URL が読み直されると、state が合わず csrf_detected になる。
# 戻り先がセッションに残っていれば、認証を最初からやり直させる。ループしないよう 1 分に 1 回まで。
CSRF_RETRY_INTERVAL = 60

retry_csrf = ->(env) {
  req = Rack::Request.new(env)
  return unless req.path_info == '/auth/failure' && req.params['message'] == 'csrf_detected'

  session = env['rack.session']
  return unless session['back_to'] && session['app_callback']
  return if session['csrf_retried_at'] && Time.now.to_i - session['csrf_retried_at'] < CSRF_RETRY_INTERVAL

  session['csrf_retried_at'] = Time.now.to_i
  [302, {'Location' => 'https://auth.dark-kuins.net/auth/github'}, []]
}

run ->(env) {
  if env['PATH_INFO'] == '/'
    [200, {}, ['o-su!']]
  elsif (res = retry_csrf.(env))
    res
  else
    app.call(env)
  end
}
