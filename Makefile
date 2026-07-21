.PHONY: build install open clean

build:
	bash scripts/package.sh

install:
	bash scripts/package.sh --install

open:
	bash scripts/package.sh --open

install-open:
	bash scripts/package.sh --install --open

clean:
	swift package clean
	rm -rf .build/App
