.PHONY: test lint build install clean

# Linux tests in a container.
test:
	docker compose run --rm test

# swift-format, shellcheck and actionlint, each in its own container.
lint:
	docker compose run --rm lint-swift
	docker compose run --rm lint-shell
	docker compose run --rm lint-actions

# macOS only: build and sign build/BlackSharkBattery.app.
build:
	./build.sh

# macOS only: build, then copy to /Applications.
install:
	./build.sh install

clean:
	rm -rf .build build SHA256SUMS *.zip
