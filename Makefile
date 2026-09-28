APP_NAME = Idasen
BUILD_DIR = build
CONFIG ?= release

.PHONY: all build test app run debug icon clean

all: app

build:
	swift build -c $(CONFIG)

test:
	swift test

## Assemble a double-clickable .app bundle in build/Idasen.app
app: icon
	CONFIG=$(CONFIG) ./Scripts/build-app.sh

icon:
	@test -f Resources/AppIcon.icns || ./Scripts/make-icon.sh

debug:
	swift build -c debug
	CONFIG=debug ./Scripts/build-app.sh

## Launch the built app
run: app
	open $(BUILD_DIR)/$(APP_NAME).app

clean:
	swift package clean
	rm -rf $(BUILD_DIR)

.PHONY: package site
## Package this Mac's architecture, with a SHA-256 checksum.
package: icon
	./Scripts/package-app.sh

## Build the static GitHub Pages site without Node dependencies.
site:
	./Scripts/build-site.sh
