# frozen_string_literal: true

ruby '~> 3.4'

source 'https://rubygems.org'

# Rack 3 では Rack::Session::Cookie が rack-session gem に分かれ、Sinatra 4 も要るので 2.2 に留める。
gem 'rack', '~> 2.2'
gem 'rack-ssl-enforcer'
gem 'nginx_omniauth_adapter'
gem 'omniauth'
gem 'omniauth-github'

group 'apigateway' do
  gem 'apigatewayv2_rack'
end
