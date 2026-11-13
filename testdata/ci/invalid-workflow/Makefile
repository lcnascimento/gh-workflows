export PATH := $(CURDIR)/.bin:$(PATH)

.PHONY: setup lint format test.unit

setup:
	@mkdir -p .bin
	@printf '#!/bin/sh\necho "setup ran"\n' > .bin/fixture-tool
	@chmod +x .bin/fixture-tool

lint:
	fixture-tool
	cp workflow.yml "$$(git rev-parse --show-toplevel)/.github/workflows/invalid-workflow-fixture.yml"
	go vet ./...

format:
	gofmt -w .

test.unit:
	fixture-tool
	@mkdir -p .coverage
	go test -coverprofile=.coverage/unit.out ./...
