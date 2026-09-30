XCODEBUILD := xcodebuild -project Luna.xcodeproj -scheme Luna -derivedDataPath DerivedData

.PHONY: gen build run test lint check dmg signed

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

# §31.1: a Developer ID build carrying the iCloud entitlements and the
# provisioning profile that grants them. Opt in: `build`, `test` and CI stay
# ad-hoc, because the certificate is on one Mac. The profile is kept out of
# the repo (*.provisionprofile is ignored) at the path below. No sandbox
# entitlement, on purpose: docs/SYNC.md.
SIGNED_APP := DerivedData/Build/Products/Release/Luna.app
IDENTITY := Developer ID Application: NovApps ApS (FUUYR6KRSH)

signed:
	$(XCODEBUILD) -configuration Release build
	cp Config/Signing/Luna_Developer_ID.provisionprofile $(SIGNED_APP)/Contents/embedded.provisionprofile
	codesign --force --options runtime --timestamp --sign "$(IDENTITY)" $(SIGNED_APP)/Contents/MacOS/luna-control
	codesign --force --options runtime --timestamp --sign "$(IDENTITY)" \
		--entitlements Config/Signing/Luna.entitlements $(SIGNED_APP)

test:
	swift test --package-path BrowserKit
	xcodebuild -scheme Luna -configuration Debug -derivedDataPath ./DerivedData test

lint:
	swiftlint lint --quiet --strict

check: lint
	Tools/check-no-appkit.sh
	Tools/check-command-bar-offline.sh

# §30.17's installer. Takes the Release build unless given a path. One image,
# and the dark one: a disk image's backdrop cannot follow the appearance
# (UI-SPEC §5.3), so the plane that ships is the plane the app looks like.
dmg:
	Tools/make-dmg.sh $(APP) $(DMG)
