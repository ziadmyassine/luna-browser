#!/bin/sh
# §9.3's acceptance check against a real history: is the page the user meant
# the Command Bar's first row after two typed characters? See
# Tests/CommandBar/RankingCheckTests.swift for the method.
#
#   Tools/ranking-check.sh [path/to/luna.sqlite]
#
# Defaults to this Mac's own database. It is never written: SQLite takes a
# read-only backup of it into a temporary folder, the test copies that again
# before opening it, and both copies are deleted afterwards. The pages and the
# misses are printed here and kept nowhere else; only the counts belong in
# docs/PERF.md.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
database="${1:-$HOME/Library/Application Support/dev.novapps.luna/luna.sqlite}"
derived="${LUNA_DERIVED_DATA:-$root/DerivedData}"
[ -f "$database" ] || { echo "ranking-check: no database at $database"; exit 1; }

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"; rm -f /tmp/luna-ranking-db' EXIT
# `mode=ro`, and `.backup` reads a consistent snapshot even while Luna is
# running and has its write-ahead log open.
sqlite3 "file:$database?mode=ro" ".backup '$scratch/luna.sqlite'"
printf '%s\n' "$scratch/luna.sqlite" > /tmp/luna-ranking-db
rm -f /tmp/luna-ranking-check.txt

cd "$root"
xcodebuild -project Luna.xcodeproj -scheme Luna -configuration Debug \
    -derivedDataPath "$derived" test -only-testing:LunaTests/RankingCheckTests \
    >/dev/null 2>&1 || echo "ranking-check: the test did not pass — see the output below"
cat /tmp/luna-ranking-check.txt 2>/dev/null || echo "ranking-check: no result was written"
rm -f /tmp/luna-ranking-check.txt
