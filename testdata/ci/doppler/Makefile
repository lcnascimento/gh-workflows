export PATH := $(CURDIR)/.bin:$(PATH)

TOKEN := dp.st.hlb-206-dummy
no-token = ! env | grep -qF '$(TOKEN)'
via-doppler = test "$$DOPPLER_TOKEN" = '$(TOKEN)' && test "$$DOPPLER_STUB" = run && "$$(cat .bin/doppler-real)" --version

.PHONY: setup lint format test.unit test.component test.integration test.e2e

setup:
	$(no-token)
	@mkdir -p .bin
	command -v doppler > .bin/doppler-real || true
	cp doppler-stub .bin/doppler
	echo "$(CURDIR)/.bin" >> "$$GITHUB_PATH"

lint:
	$(no-token)
	go vet ./...

format:
	$(no-token)
	gofmt -w .

test.unit test.component:
	$(no-token)
	@mkdir -p .coverage
	go test -coverprofile=.coverage/$(@:test.%=%).out ./...

test.integration test.e2e:
	$(via-doppler)
	@mkdir -p .coverage
	go test -coverprofile=.coverage/$(@:test.%=%).out ./...
