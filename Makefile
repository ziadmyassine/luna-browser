XCODEBUILD := xcodebuild -project Luna.xcodeproj -scheme Luna -derivedDataPath DerivedData

.PHONY: gen build run test uitest lint check dmg signed instruments

gen:
	xcodegen generate

# An ad-hoc signature's designated requirement is the build's cdhash, so to
# macOS privacy every rebuild is a new app and loses its grants (Screen
# Recording, for Report a Bug). Re-signed with a certificate, the requirement
# names the certificate and survives rebuilds. Only when this Mac's keychain
# has the identity: CI and a Mac without it stay ad-hoc. Any code-signing
# certificate works: `export LUNA_SIGN_IDENTITY="Apple Development: …"`.
# Re-signed here rather than through CODE_SIGN_IDENTITY, which xcodebuild also
# applies to the package resource bundles, and those then demand a team.
DEBUG_APP := DerivedData/Build/Products/Debug/Luna.app
LUNA_SIGN_IDENTITY ?= Developer ID Application: NovApps ApS (FUUYR6KRSH)
HAS_IDENTITY := $(shell security find-identity -v -p codesigning 2>/dev/null | grep -F '"$(LUNA_SIGN_IDENTITY)"')
DEV_CODESIGN := codesign --force --timestamp=none --preserve-metadata=entitlements --sign "$(LUNA_SIGN_IDENTITY)"

build:
	$(XCODEBUILD) -configuration Debug build
ifneq ($(HAS_IDENTITY),)
	$(DEV_CODESIGN) $(DEBUG_APP)/Contents/MacOS/*
	$(DEV_CODESIGN) $(DEBUG_APP)
endif

# `touch` + `lsregister` are not ceremony. Launch Services caches an app's
# icon against its path, and a Debug build always has the same path — so a
# re-exported icon keeps showing the old art in the Dock and the Finder until
# the bundle's date changes and it is re-registered. The bundle was right; the
# cache was stale.
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

run: build
	touch $(DEBUG_APP)
	$(LSREGISTER) -f $(DEBUG_APP)
	open $(DEBUG_APP)

# §31.1: a Developer ID build carrying the iCloud entitlements and the
# provisioning profile that grants them. Opt in, because the certificate is on
# one Mac; `build` signs with it too, but without those entitlements. The
# profile is kept out of the repo (*.provisionprofile is ignored) at the path
# below. No sandbox entitlement, on purpose: docs/SYNC.md.
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

# §24.1. Takes the pointer and the keyboard and brings Luna to the front, so it
# is not part of `test`: run it on CI, or on a Mac nobody is using.
uitest:
	xcodebuild -project Luna.xcodeproj -scheme LunaUITests -derivedDataPath DerivedData -configuration Debug -destination 'platform=macOS' test

lint:
	swiftlint lint --quiet --strict

# §19.5: Time Profiler, Allocations and Leaks over Tools/perf's `page` scenario,
# appended to docs/PERF.md. No window and no activation — see the script.
instruments:
	Tools/perf/instruments.sh

check: lint
	Tools/check-no-appkit.sh
	Tools/check-command-bar-offline.sh

# §30.17's installer. Takes the Release build unless given a path. One image,
# and the dark one: a disk image's backdrop cannot follow the appearance
# (UI-SPEC §5.3), so the plane that ships is the plane the app looks like.
dmg:
	Tools/make-dmg.sh $(APP) $(DMG)
