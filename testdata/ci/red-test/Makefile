export PATH := $(CURDIR)/.bin:$(PATH)

.PHONY: setup lint format test.unit

setup:
	@mkdir -p .bin
	@printf '#!/bin/sh\necho "setup ran"\n' > .bin/fixture-tool
	@chmod +x .bin/fixture-tool

lint:
	fixture-tool
	go vet ./...

format:
	gofmt -w .

test.unit:
	fixture-tool
	@mkdir -p .coverage
	go test -coverprofile=.coverage/unit.out ./...
