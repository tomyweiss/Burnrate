.PHONY: build install open clean install-dev

build:
	bash scripts/package.sh

install:
	bash scripts/package.sh --install

install-dev:
	bash scripts/package.sh --dev --install --open

open:
	bash scripts/package.sh --open

install-open:
	bash scripts/package.sh --install --open

clean:
	swift package clean
	rm -rf .build/App
