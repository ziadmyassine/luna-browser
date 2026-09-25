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
	Tools/check-command-bar-offline.sh

# §30.17's installer. Takes the Release build unless given a path. One image,
# and the dark one: a disk image's backdrop cannot follow the appearance
# (UI-SPEC §5.3), so the plane that ships is the plane the app looks like.
dmg:
	Tools/make-dmg.sh $(APP) $(DMG)
