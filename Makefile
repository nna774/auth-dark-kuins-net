.PHONY: deploy preview bundler dualstack
all: app

app: bundler
# native 拡張を含む gem が Lambda (Linux x86_64) で動くよう、Lambda のイメージの中でビルドする。
bundler:
	rm -rf vendor/bundle .bundle
	docker run --rm --platform linux/arm64 --entrypoint /bin/sh -v "$(CURDIR)":/var/task -w /var/task public.ecr.aws/lambda/ruby:3.4 \
		-c 'microdnf install -y gcc make >/dev/null && bundle config set --local path vendor/bundle && bundle config set --local deployment true && bundle install'

# 秘密は変える時だけ環境変数で渡す: GITHUB_KEY GITHUB_SECRET RACK_SESSION_KEY RACK_SESSION_SECRET
# 渡さなかったものは、SAM がスタックの前回の値を引き継ぐ (空の値で上書きはしない)。
deploy: app
	@set --; \
	for pair in GithubKey:GITHUB_KEY GithubSecret:GITHUB_SECRET RackSessionKey:RACK_SESSION_KEY RackSessionSecret:RACK_SESSION_SECRET; do \
		p=$${pair%%:*}; v=$${pair##*:}; eval "val=\$$$$v"; \
		if [ -n "$$val" ]; then set -- "$$@" "$$p=$$val"; fi; \
	done; \
	if [ $$# -gt 0 ]; then set -- --parameter-overrides "$$@"; fi; \
	sam deploy --region ap-northeast-1 --capabilities CAPABILITY_IAM --s3-bucket nana-lambda --stack-name auth-dark-kuins-net "$$@"
	$(MAKE) dualstack

# SAM は HttpApi の Domain で IpAddressType を渡せない (SAM CLI 1.171 時点) ので、deploy の後に直接 dualstack にする。
# v4 だと、EC2 (tsugu) の nginx から Lambda へ、一度家を経由して AWS に戻ってしまう。
# 同じ値の update は何度流しても安全。CloudFormation がドメインを更新して設定が戻っても、次の deploy で直る。
# 証明書などは今の値を読み直して引き継ぐ。aws cli は IpAddressType に対応した新しいもの (2.39 以降) が要る。
dualstack:
	@aws apigatewayv2 get-domain-name --region ap-northeast-1 --domain-name auth.dark-kuins.net --query 'DomainNameConfigurations[0]' --output json \
	| jq -r '"CertificateArn=\(.CertificateArn),EndpointType=\(.EndpointType),SecurityPolicy=\(.SecurityPolicy),IpAddressType=dualstack"' \
	| xargs -I{} aws apigatewayv2 update-domain-name --region ap-northeast-1 --domain-name auth.dark-kuins.net --domain-name-configurations {} \
		--query 'DomainNameConfigurations[0].{ipAddressType:IpAddressType,status:DomainNameStatus}'

preview: app
	sam local start-api
