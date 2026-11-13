export PATH := $(CURDIR)/.bin:$(PATH)

.PHONY: setup lint format test.unit test.integration test.e2e

setup:
	@mkdir -p .bin

lint:
	go vet ./...

format:
	gofmt -w .

test.unit test.integration test.e2e:
	@mkdir -p .coverage
	go test -coverprofile=.coverage/$(@:test.%=%).out ./...
