export PATH := $(CURDIR)/.bin:$(PATH)

.PHONY: setup lint format test.unit

setup:
	@mkdir -p .bin

lint:
	test "$$(node --version)" = "v$$(cat .nvmrc)"

format:

test.unit:
	@mkdir -p .coverage
	node --test --experimental-test-coverage --test-reporter=spec --test-reporter-destination=stdout --test-reporter=lcov --test-reporter-destination=.coverage/unit.lcov sum.test.ts
