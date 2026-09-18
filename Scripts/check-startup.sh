#!/usr/bin/env bash
set -euo pipefail

executable="${1:?Usage: bash Scripts/check-startup.sh /path/to/MacMonitor}"
startup_log="$(mktemp -t MacMonitor-startup)"

# The launch argument enables hiding without changing the saved preference.
NSUnbufferedIO=YES "$executable" -MacMonitor.HideMenuBarIcon YES > "$startup_log" 2>&1 &
startup_pid=$!
trap 'kill "$startup_pid" 2>/dev/null || true; wait "$startup_pid" 2>/dev/null || true; rm -f "$startup_log"' EXIT

for _ in {1..100}; do
    if ! kill -0 "$startup_pid" 2>/dev/null; then
        break
    fi
    if grep -qF '[AppDelegate] Mac Monitor started successfully.' "$startup_log"; then
        sleep 1
        if kill -0 "$startup_pid" 2>/dev/null; then
            echo 'PASS: hidden-icon startup completed and the app stayed running.'
            exit 0
        fi
        break
    fi
    sleep 0.1
done

cat "$startup_log"
echo 'FAIL: hidden-icon startup crashed or did not complete.' >&2
exit 1
