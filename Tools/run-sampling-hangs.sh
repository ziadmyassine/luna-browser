#!/bin/sh
# Runs a test command, and if its output stops moving for <quiet> seconds,
# samples every test process and prints where each thread is before failing.
# The Luna test host is matched by its DerivedData path only, so the Luna in
# /Applications is never touched.
#
# CI's runner has three cores, and twice a suite has stalled there that never
# stalls on a developer Mac. A job time limit only ends the run; it says nothing
# about which test was waiting on what. This prints the stacks.
#
# Usage: Tools/run-sampling-hangs.sh <quiet seconds> <command> [args…]
set -u
quiet="$1"
shift

log=$(mktemp)
"$@" >"$log" 2>&1 &
pid=$!
shown=0
last=$(date +%s)
while kill -0 "$pid" 2>/dev/null; do
	sleep 5
	lines=$(wc -l <"$log")
	if [ "$lines" -gt "$shown" ]; then
		sed -n "$((shown + 1)),${lines}p" "$log"
		shown=$lines
		last=$(date +%s)
	elif [ $(($(date +%s) - last)) -ge "$quiet" ]; then
		echo "::error::No test output for ${quiet} s. Sampling the test processes."
		for p in $(pgrep -f 'swiftpm-testing-helper|xctest|DerivedData/.*/Luna.app/Contents/MacOS/Luna'); do
			echo "===== $(ps -o command= -p "$p" | cut -c1-160) (pid $p)"
			sample "$p" 2 2>/dev/null | sed -n '/^Call graph:/,/^Total number in stack/p' | head -400
		done
		kill "$pid" 2>/dev/null
		pkill -f 'swiftpm-testing-helper|xctest|DerivedData/.*/Luna.app/Contents/MacOS/Luna' 2>/dev/null
		exit 1
	fi
done
sed -n "$((shown + 1)),\$p" "$log"
wait "$pid"
