.PHONY: build install open clean install-dev watch-dev

build:
	bash scripts/package.sh

install:
	bash scripts/package.sh --install

install-dev:
	bash scripts/package.sh --dev --install --open

# Rebuild + relaunch Burnrate-dev on Swift/resource changes (debug, fast).
watch-dev:
	bash scripts/dev-watch.sh

open:
	bash scripts/package.sh --open

install-open:
	bash scripts/package.sh --install --open

clean:
	swift package clean
	rm -rf .build/App
