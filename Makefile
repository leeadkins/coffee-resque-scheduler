generate-js: deps
	@mkdir -p lib
	@find src -name '*.coffee' |xargs coffee -c -o lib

remove-js:
	@rm -rf lib/

deps:
	@test `which coffee` || echo 'You need to have CoffeeScript in your PATH.\nPlease install it using `npm install coffee-script`.'
	@test `which npm` || echo 'You need to have npm in your PATH.\nPlease install it. (See https://github.com/isaacs/npm)'

publish: generate-js test
	npm publish

dev-install: generate-js
	npm link .

.PHONY: all
