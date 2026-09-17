XCODEBUILD := xcodebuild -project Luna.xcodeproj -scheme Luna -derivedDataPath DerivedData

.PHONY: gen build run test lint fmt check

gen:
	xcodegen generate

build:
	$(XCODEBUILD) -configuration Debug build

run: build
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
