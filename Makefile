.PHONY: deploy preview bundler
all: app

app: bundler
# native 拡張を含む gem が Lambda (Linux x86_64) で動くよう、Lambda のイメージの中でビルドする。
bundler:
	rm -rf vendor/bundle .bundle
	docker run --rm --platform linux/arm64 --entrypoint /bin/sh -v "$(CURDIR)":/var/task -w /var/task public.ecr.aws/lambda/ruby:3.4 \
		-c 'microdnf install -y gcc make >/dev/null && bundle config set --local path vendor/bundle && bundle config set --local deployment true && bundle install'

# 秘密は環境変数で渡す: GITHUB_KEY GITHUB_SECRET RACK_SESSION_KEY RACK_SESSION_SECRET
deploy: app
	@for v in GITHUB_KEY GITHUB_SECRET RACK_SESSION_KEY RACK_SESSION_SECRET; do \
		eval "[ -n \"\$$$$v\" ]" || { echo "$$v が空。環境変数が空で上書きされるのでやめる" >&2; exit 1; }; \
	done
	sam deploy --region ap-northeast-1 --capabilities CAPABILITY_IAM --s3-bucket nana-lambda --stack-name auth-dark-kuins-net \
		--parameter-overrides GithubKey="$$GITHUB_KEY" GithubSecret="$$GITHUB_SECRET" RackSessionKey="$$RACK_SESSION_KEY" RackSessionSecret="$$RACK_SESSION_SECRET"

preview: app
	sam local start-api
