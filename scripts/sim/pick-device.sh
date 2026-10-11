#!/usr/bin/env bash
# Picks (or creates) the Simulator used by the proof job and prints its UDID on stdout.
# Prefers iPhone 17 Pro Max, then iPhone 16 Pro Max; both render 1320x2868 screenshots.
# Writes a human-readable description to $1 when given.
set -euo pipefail
DEVICE_TXT="${1:-}"

pick() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys, re
wanted = sys.argv[1]
data = json.load(sys.stdin)
best = None
for runtime, devices in data["devices"].items():
    if "iOS" not in runtime: continue
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    ver = (int(m.group(1)), int(m.group(2))) if m else (0, 0)
    for d in devices:
        if d.get("name") == wanted and d.get("isAvailable", True):
            if best is None or ver > best[0]: best = (ver, d["udid"], runtime)
if best: print(best[1])
' "$1"
}

create() {
  local name="$1" devtype="$2"
  local runtime
  runtime=$(xcrun simctl list runtimes available -j | python3 -c '
import json, sys
rts = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r.get("isAvailable", True)]
rts.sort(key=lambda r: [int(x) for x in r["version"].split(".")])
print(rts[-1]["identifier"] if rts else "")
')
  [ -n "$runtime" ] || return 1
  xcrun simctl create "$name" "$devtype" "$runtime" 2>/dev/null || return 1
}

UDID=$(pick "iPhone 17 Pro Max" || true)
if [ -z "$UDID" ]; then UDID=$(create "iPhone 17 Pro Max" "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max" || true); fi
if [ -z "$UDID" ]; then UDID=$(pick "iPhone 16 Pro Max" || true); fi
if [ -z "$UDID" ]; then UDID=$(create "iPhone 16 Pro Max" "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max" || true); fi
if [ -z "$UDID" ]; then
  echo "No iPhone 17/16 Pro Max simulator available" >&2
  xcrun simctl list devices available >&2
  exit 1
fi

if [ -n "$DEVICE_TXT" ]; then
  {
    echo "udid: $UDID"
    xcrun simctl list devices -j | python3 -c '
import json, sys
udid = sys.argv[1]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for d in devices:
        if d["udid"] == udid:
            print("name: " + d["name"]); print("runtime: " + runtime); print("deviceType: " + d.get("deviceTypeIdentifier", "?"))
' "$UDID"
    echo "xcode: $(xcodebuild -version | tr '\n' ' ')"
    echo "xcode-path: $(xcode-select -p)"
    echo "macos: $(sw_vers -productVersion) ($(uname -m))"
    echo "runner: ${RUNNER_NAME:-local} image=${ImageOS:-?} ${ImageVersion:-?}"
  } > "$DEVICE_TXT"
fi
echo "$UDID"
