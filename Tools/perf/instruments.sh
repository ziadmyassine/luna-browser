#!/bin/sh
#
# Tools/perf/instruments.sh — the §19.5 Instruments pass.
#
#   make instruments                 five rounds of the `page` scenario
#   Tools/perf/instruments.sh 10     ten
#
# Records Time Profiler, Allocations and Leaks over the harness's `page`
# scenario (local pages through the real `TabController`), keeps the traces in
# Tools/perf/.build/instruments/ for Instruments.app, and appends the headline
# numbers to docs/PERF.md's run log.
#
# Why the harness and not Luna.app: the app activates itself and puts a window
# on screen, and `CFFIXED_USER_HOME` does not move `UserDefaults`, so a profiled
# copy would write the owner's real preferences. The harness is `.accessory`,
# has no window, and keeps its state in temporary files and non-persistent
# data stores. Animation Hitches needs frames presented on a display, so it is
# not recorded here; docs/PERF.md says what a foreground run would take.
#
# Three things that are not ceremony:
#  · The binary is copied out of the checkout. Under ~/Desktop, a process
#    launched by xctrace blocked in dyld opening its own executable and never
#    started — most likely the folder's privacy protection.
#  · The copy is signed with `get-task-allow`, as Xcode signs a Debug build.
#    Without it, Allocations left the target suspended until the time limit.
#  · Leaks attaches to a harness kept alive by `LUNA_PERF_LINGER`. Launched,
#    it takes its memory graph after the process has exited, and fails.
#
# "could not lock kperf", or a recording that never ends after the target
# exits, is a `DTServiceHub` left over from an earlier run: `pkill -9 DTServiceHub`.
#
# xctrace's export has no table for Allocations or Leaks, so their numbers are
# read with `leaks` and `heap` from the same lingering process: what is still
# allocated once the scenario has hibernated every tab.
#
set -e

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PERF="$ROOT/Tools/perf"
REPEATS=${1:-5}
OUT="$PERF/.build/instruments/$(date '+%Y-%m-%d-%H%M')"
WORK=$(mktemp -d -t luna-instruments)
SUMMARY="$OUT/summary.txt"
mkdir -p "$OUT"
trap 'rm -rf "$WORK"' EXIT

cd "$PERF"
swift build -c release >/dev/null
cp -R .build/release/LunaPerf .build/release/*.bundle "$WORK/"
cat > "$WORK/entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.get-task-allow</key><true/></dict></plist>
PLIST
codesign --force --sign - --entitlements "$WORK/entitlements.plist" "$WORK/LunaPerf" 2>/dev/null
BIN="$WORK/LunaPerf"

# record <template> <xctrace arguments…>
record() {
    template=$1
    shift
    name=$(echo "$template" | tr -d ' ')
    echo "== $template"
    xcrun xctrace record --template "$template" --no-prompt --output "$OUT/$name.trace" "$@" \
        > "$OUT/$name.log" 2>&1 || { echo "   failed:"; sed 's/^/   /' "$OUT/$name.log"; }
}

record "Time Profiler" --time-limit 10m --launch -- "$BIN" page "$REPEATS"
xcrun xctrace export --input "$OUT/TimeProfiler.trace" \
    --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' > "$WORK/time.xml"
xcrun xctrace export --input "$OUT/TimeProfiler.trace" \
    --xpath '/trace-toc/run[@number="1"]/data/table[@schema="potential-hangs"]' > "$WORK/hangs.xml"

record Allocations --time-limit 10m --launch -- "$BIN" page "$REPEATS"

MallocStackLogging=1 LUNA_PERF_LINGER=300 "$BIN" page "$REPEATS" > "$WORK/linger.txt" 2>/dev/null &
waited=0
until grep -q '^LINGER' "$WORK/linger.txt"; do
    sleep 1
    waited=$((waited + 1))
    [ $waited -lt 600 ] || { echo "the harness never finished its scenario"; exit 1; }
done
PID=$(sed -n 's/^LINGER //p' "$WORK/linger.txt")
record Leaks --time-limit 5s --attach "$PID"
leaks "$PID" > "$WORK/leaks.txt" 2>/dev/null || true
heap -s "$PID" > "$WORK/heap.txt" 2>/dev/null || true
{ kill "$PID" && wait "$PID"; } 2>/dev/null || true

/usr/bin/python3 - "$WORK" "$REPEATS" > "$SUMMARY" <<'PY'
import collections, re, sys
import xml.etree.ElementTree as ET

work, repeats = sys.argv[1], sys.argv[2]

def rows(path):
    root = ET.parse(path).getroot()
    ids = {el.get("id"): el for el in root.iter() if el.get("id")}
    deref = lambda el: ids[el.get("ref")] if el is not None and el.get("ref") else el
    return root.iter("row"), deref

# Time Profiler: self time by leaf frame, and inclusive time by the frames that
# are Luna's (BrowserKit is linked into the harness binary), the harness's own
# scaffolding left out.
samples, deref = rows(f"{work}/time.xml")
total = 0
leaf = collections.Counter()
ours = collections.Counter()
scaffolding = re.compile(r"#\d| in $|LunaPerf_main|autoreleasepool|^main$|^pump")
for row in samples:
    tagged = deref(row.find("tagged-backtrace"))
    if tagged is None:
        continue
    trace = deref(tagged.find("backtrace"))
    frames = [deref(f) for f in trace.findall("frame")] if trace is not None else []
    if not frames:
        continue
    total += 1
    leaf[frames[0].get("name")] += 1
    seen = set()
    for frame in frames:
        binary = deref(frame.find("binary"))
        name = frame.get("name").removeprefix("specialized ")
        if binary is not None and binary.get("name") == "LunaPerf" and not scaffolding.search(name) and name not in seen:
            seen.add(name)
            ours[name] += 1
hangs = sum(1 for _ in rows(f"{work}/hangs.xml")[0])

pct = lambda n: f"{100 * n / total:.1f} %" if total else "-"
print(f"TIME page x{repeats}: {total} 1 ms samples of the harness process on CPU, {hangs} hangs over 250 ms")
for name, count in ours.most_common(6):
    print(f"TIME   ours  {pct(count):>7}  {name}")
for name, count in leaf.most_common(5):
    print(f"TIME   self  {pct(count):>7}  {name}")

leaks = open(f"{work}/leaks.txt", errors="replace").read()
heap = open(f"{work}/heap.txt", errors="replace").read()
def grab(pattern, text):
    match = re.search(pattern, text)
    return match[1] if match else "?"
nodes, live = grab(r"(\d+) nodes malloced", leaks), grab(r"nodes malloced for (\d+ KB)", leaks)
footprint, peak = grab(r"Physical footprint:\s+(\S+)", leaks), grab(r"Physical footprint \(peak\):\s+(\S+)", leaks)
print(f"ALLOC page x{repeats}, after the scenario: {nodes} nodes, {live} live; footprint {footprint}, peak {peak}")
for cls in ("WKWebView", "WKNavigation", "WKWebViewConfiguration"):
    match = re.search(r"^\s*(\d+)\s+(\d+)\s+\S+\s+" + re.escape(cls) + r"\s", heap, re.M)
    print(f"ALLOC   {cls}: " + (f"{match[1]} live, {match[2]} bytes" if match else "none live"))
count, size = grab(r"(\d+) leaks for", leaks), grab(r"leaks for (\d+) total", leaks)
roots = collections.Counter(re.findall(r"^\s{0,8}\d+ \([^)]*\) (ROOT (?:CYCLE|LEAK): <[^ >]+)", leaks, re.M))
through_luna = len(re.findall(r"^\s*\d+\s+LunaPerf\s", leaks, re.M))
print(f"LEAKS page x{repeats}: {count} leaks, {size} bytes; roots: "
      + (", ".join(f"{n}x {r}>" for r, n in roots.most_common()) or "none")
      + f"; frames of Luna's code in leak stacks: {through_luna}")
print("HITCHES not recorded: Animation Hitches needs Luna's window on a display (docs/PERF.md, §19.5)")
PY

cat "$SUMMARY"
{
    echo ""
    echo "### $(date '+%Y-%m-%d %H:%M') — Instruments, $(sysctl -n machdep.cpu.brand_string), \
$(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion), Xcode $(xcrun xctrace version | sed 's/xctrace version //')"
    echo ""
    echo '```'
    cat "$SUMMARY"
    echo '```'
} >> "$ROOT/docs/PERF.md"
echo ""
echo "traces in $OUT; appended to docs/PERF.md"
