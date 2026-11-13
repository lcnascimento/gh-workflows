export PATH := $(CURDIR)/.bin:$(PATH)

# renovate: datasource=pypi depName=ruff
RUFF_VERSION := 0.17.5
# renovate: datasource=pypi depName=coverage
COVERAGE_VERSION := 7.17.3

.PHONY: setup lint format test.unit

setup:
	@mkdir -p .bin

lint:
	test "$$(uv run python --version)" = "Python $$(cat .python-version)"
	uvx ruff@$(RUFF_VERSION) check .

format:
	uvx ruff@$(RUFF_VERSION) format .

test.unit:
	@mkdir -p .coverage
	uv run --with coverage==$(COVERAGE_VERSION) coverage run --data-file=.coverage/unit.data -m unittest -v
	uv run --with coverage==$(COVERAGE_VERSION) coverage xml --data-file=.coverage/unit.data -o .coverage/unit.xml
