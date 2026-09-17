#!/bin/sh
#
# Tools/perf/run.sh — the §19.1 measurement pass.
#
#   ./Tools/perf/run.sh            everything
#   ./Tools/perf/run.sh tabs       the 40-tab memory budget only
#   ./Tools/perf/run.sh launch     cold launch + idle cost only
#   ./Tools/perf/run.sh ui         the command bar and sidebar budgets only
#
# Every run appends its summary lines to docs/PERF.md with the date and the
# machine, which is the whole point: one number is a reading, two are a trend
# (§19.5).
#
# Notes on what this can and cannot do:
#  · "Cold launch" here is a warm-file-cache launch. Emptying the page cache
#    needs `purge`, which needs root, so the number is the best case for disk
#    and the honest case for everything else.
#  · The launch scenario replaces Luna's database with a seeded 40-tab session
#    and puts the real one back afterwards. It is a `mv`, not a delete — if this
#    script is killed halfway, the original is at <support>.perfbak.
#
set -e

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PERF="$ROOT/Tools/perf"
APP="$ROOT/DerivedData/Build/Products/Debug/Luna.app/Contents/MacOS/Luna"
SUPPORT="$HOME/Library/Application Support/dk.novapps.luna"
LOG=$(mktemp -t luna-perf)
WHAT=${1:-all}

cd "$PERF"
swift build -c release >/dev/null 2>&1 && BIN="$PERF/.build/release/LunaPerf" || {
    swift build >/dev/null
    BIN="$PERF/.build/debug/LunaPerf"
}
echo "harness: $BIN"

run_tabs() {
    echo "== §19.1 memory: 40 tabs, 3 Spaces, 6 live (budget 3.5 GB) =="
    "$BIN" tabs 40 3 6 2>/dev/null | tee -a "$LOG"
}

run_launch() {
    [ -x "$APP" ] || { echo "no build at $APP — run 'make build' first"; return 0; }
    echo "== §19.1 cold launch (budget 800 ms), with a seeded 40-tab session =="
    # Luna's real database goes aside, not away.
    [ -d "$SUPPORT" ] && mv "$SUPPORT" "$SUPPORT.perfbak"
    "$BIN" seed "$SUPPORT/luna.sqlite" 3 40
    "$BIN" launch "$APP" 5 2>/dev/null | tee -a "$LOG"
    rm -rf "$SUPPORT"
    [ -d "$SUPPORT.perfbak" ] && mv "$SUPPORT.perfbak" "$SUPPORT"
    return 0
}

run_ui() {
    echo "== §19.1 command bar (budget 100 ms) and sidebar frame cost (budget 8.33 ms) =="
    cd "$ROOT"
    # The opt-in is a marker file: `xcodebuild test` does not hand its
    # environment to a hosted unit test's host app, so an env var never arrives
    # and the tests skip themselves in silence. See BudgetTests.
    : > /tmp/luna-perf-ui.txt
    touch /tmp/luna-perf-enabled
    xcodebuild -project Luna.xcodeproj -scheme Luna -configuration Debug \
        -derivedDataPath ./DerivedData test -only-testing:LunaTests/BudgetTests \
        >/dev/null 2>&1 || echo "  (a budget assertion failed — see the numbers below)"
    rm -f /tmp/luna-perf-enabled
    tee -a "$LOG" < /tmp/luna-perf-ui.txt
}

case "$WHAT" in
    tabs) run_tabs ;;
    launch) run_launch ;;
    ui) run_ui ;;
    *) run_tabs; run_launch; run_ui ;;
esac

{
    echo ""
    echo "### $(date '+%Y-%m-%d %H:%M') — $(sysctl -n machdep.cpu.brand_string), \
$(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
    echo ""
    echo '```'
    grep -E "^(LAUNCH|IDLE|TABS|HIBERNATED|PERF) " "$LOG" || echo "(no summary lines — see the run output)"
    echo '```'
} >> "$ROOT/docs/PERF.md"

echo ""
echo "appended to docs/PERF.md"
