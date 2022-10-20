.PHONY: deploy preview
all: app

app: bundler
bundler:
	bundle config set --local path 'vendor/bundle'
	bundle config set --local deployment 'true'
	bundle install

deploy: app
	sam deploy --region ap-northeast-1 --capabilities CAPABILITY_IAM --s3-bucket nana-lambda --stack-name auth-dark-kuins-net

preview: app
	sam local start-api
