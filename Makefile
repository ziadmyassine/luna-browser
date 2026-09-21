XCODEBUILD := xcodebuild -project Luna.xcodeproj -scheme Luna -derivedDataPath DerivedData

.PHONY: gen build run test lint fmt check dmg

gen:
	xcodegen generate

build:
	$(XCODEBUILD) -configuration Debug build

# `touch` + `lsregister` are not ceremony. Launch Services caches an app's
# icon against its path, and a Debug build always has the same path — so a
# re-exported icon keeps showing the old art in the Dock and the Finder until
# the bundle's date changes and it is re-registered. The bundle was right; the
# cache was stale.
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

run: build
	touch DerivedData/Build/Products/Debug/Luna.app
	$(LSREGISTER) -f DerivedData/Build/Products/Debug/Luna.app
	open DerivedData/Build/Products/Debug/Luna.app

test:
	swift test --package-path BrowserKit
	xcodebuild -scheme Luna -configuration Debug -derivedDataPath ./DerivedData test

lint:
	swiftlint lint --quiet --strict

fmt:
	swiftformat .

check: lint
	Tools/check-no-appkit.sh

# §30.17's installer. Takes the Release build unless given a path.
#
# Two images, because a disk image's backdrop is one picture in the volume's
# `.DS_Store` and nothing re-reads it when the appearance changes — measured,
# UI-SPEC §5.3. The only place a Mac's appearance can pick the art is the
# download, so a release publishes both and the page chooses on
# `prefers-color-scheme`. `Luna.dmg` is the one to link when it cannot.
# Spelled out rather than left to the script's own defaults, because the
# second line below has to name the same app and a neighbouring file.
APP ?= DerivedData/Build/Products/Release/Luna.app
DMG ?= build/Luna.dmg
DMG_LIGHT := $(patsubst %.dmg,%-light.dmg,$(DMG))

dmg:
	Tools/make-dmg.sh $(APP) $(DMG)
	Tools/make-dmg.sh $(APP) $(DMG_LIGHT) --light
