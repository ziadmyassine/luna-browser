#!/bin/sh
# BrowserKit is the engine layer: Foundation + WebKit only, so an iOS companion
# stays possible (TODO.md §25.5). AppKit types belong in UI/ or Design/.
set -eu
src="$(cd "$(dirname "$0")/.." && pwd)/BrowserKit/Sources"
[ -d "$src" ] || { echo "check-no-appkit: $src does not exist"; exit 1; }

banned='import (AppKit|Cocoa)|NS(App|Application|Appearance|BezierPath|Button|Color|Cursor|Event|Font|Image|Menu|MenuItem|Pasteboard|Responder|ScrollView|SplitView|StackView|TextField|TextView|ToolbarItem|View|ViewController|VisualEffectView|Window|WindowController|Workspace)\b'

# Strip line comments before matching: a file that *documents* this rule ("may not
# import AppKit") is not a violation of it. Stripping can only hide a match, never
# invent one. ponytail: line comments only; add /* */ handling if it ever matters.
hits=$(find "$src" -name '*.swift' | while IFS= read -r f; do
	sed 's|//.*||' "$f" | grep -nE "$banned" | sed "s|^|${f}:|"
done)

if [ -n "$hits" ]; then
	echo "check-no-appkit: AppKit leaked into BrowserKit (TODO.md §25.5)."
	echo "$hits" | sed 's/^/  /'
	echo "Move the UI type into UI/ or Design/ and keep BrowserKit on Foundation + WebKit."
	exit 1
fi

echo "check-no-appkit: BrowserKit is AppKit-free."
