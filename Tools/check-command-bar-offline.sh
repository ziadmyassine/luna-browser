#!/bin/sh
# UI-SPEC §9.6: the Command Bar sends nothing anywhere, made structurally true
# rather than a comment. Search suggestions are the one §9.2 source that would
# need the network, and they are not built, so no file under UI/CommandBar has
# any business naming a networking type.
#
# A script, not an XCTest: the test ran inside the app's test host, which has
# to be granted the Documents folder to read the sources, and macOS asks again
# after every rebuild. Unanswered, the suite hung on it.
set -eu
src="$(cd "$(dirname "$0")/.." && pwd)/UI/CommandBar"
[ -d "$src" ] || { echo "check-command-bar-offline: $src does not exist"; exit 1; }

banned='URLSession|NSURLConnection|NWConnection|NWBrowser|CFNetwork|dataTask|downloadTask|URLRequest|Network\.'

# Line comments stripped first, as check-no-appkit does: a file that documents
# the rule is not a violation of it.
hits=$(find "$src" -name '*.swift' | while IFS= read -r f; do
	sed 's|//.*||' "$f" | grep -nE "$banned" | sed "s|^|${f}:|"
done)

if [ -n "$hits" ]; then
	echo "check-command-bar-offline: the Command Bar names a networking type (UI-SPEC §9.6)."
	echo "$hits" | sed 's/^/  /'
	exit 1
fi

echo "check-command-bar-offline: the Command Bar is local-only."
