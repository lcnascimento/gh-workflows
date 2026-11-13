export PATH := $(CURDIR)/.bin:$(PATH)

.PHONY: setup lint format test.unit

setup:
	@mkdir -p .bin

lint:
	test "$$(tofu version -json | jq -r .terraform_version)" = "$$(cat .opentofu-version)"
	tofu init -backend=false -input=false
	tofu validate

format:
	tofu fmt -recursive

test.unit:
	tofu init -backend=false -input=false
	tofu test
