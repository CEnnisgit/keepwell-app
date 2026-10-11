#!/usr/bin/env bash
# Launches every DEBUG screenshot hook, waits until the app reports the hook finished (kw-state.json),
# lets the screen settle, captures a Simulator screenshot and validates the recorded state.
# Usage: capture.sh <udid> <out-dir> <state-dir>
set -euo pipefail
UDID="$1"; OUT="$2"; STATE="$3"
BUNDLE="com.nimbuswebdesign.keepwell"
HOOKS=(home swipe month onthisday screenshots duplicates tray explainer freed paywall settings)
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT" "$STATE"
TMP=$(mktemp -d)
STATE_FILE="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)/Documents/kw-state.json"

wait_ready() {  # until the app says the hook finished (max $1 seconds)
  local max="$1" hook="$2" waited=0
  while [ "$waited" -lt "$max" ]; do
    python3 "$HERE/state-check.py" "$hook" "$STATE_FILE" ready >/dev/null 2>&1; rc=$?
    [ "$rc" -eq 0 ] && return 0
    if [ "$rc" -eq 1 ]; then echo "  state check failed:"; cat "$STATE_FILE" 2>/dev/null; return 1; fi
    sleep 2; waited=$((waited + 2))
  done
  echo "  state never became ready after ${max}s:"; cat "$STATE_FILE" 2>/dev/null || echo "  (no state file)"
  return 1
}

settle_and_capture() {
  # Screenshots until two consecutive captures are byte-identical (the status bar clock is frozen),
  # so thumbnails, sheets and animations are given time to finish.
  local target="$1" max_wait="$2"
  local prev="$TMP/prev.png" cur="$TMP/cur.png" waited=0
  sleep 3
  xcrun simctl io "$UDID" screenshot --type=png "$prev" >/dev/null 2>&1
  while [ "$waited" -lt "$max_wait" ]; do
    sleep 3; waited=$((waited + 3))
    xcrun simctl io "$UDID" screenshot --type=png "$cur" >/dev/null 2>&1
    if cmp -s "$prev" "$cur"; then break; fi
    mv "$cur" "$prev"
  done
  xcrun simctl io "$UDID" screenshot --type=png "$target"
  echo "  settled after ~${waited}s"
}

fail=0
i=0
for hook in "${HOOKS[@]}"; do
  i=$((i + 1))
  file=$(printf "%s/%02d-%s.png" "$OUT" "$i" "$hook")
  echo "== $hook -> $file"
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  rm -f "$STATE_FILE"
  sleep 1
  xcrun simctl launch "$UDID" "$BUNDLE" -KWScreen "$hook"
  case "$hook" in
    duplicates) wait_ready 150 "$hook" || fail=1 ;;
    *)          wait_ready 60 "$hook" || fail=1 ;;
  esac
  settle_and_capture "$file" 45
  cp "$STATE_FILE" "$(printf "%s/%02d-%s.json" "$STATE" "$i" "$hook")" 2>/dev/null || true
  python3 "$HERE/state-check.py" "$hook" "$STATE_FILE" || fail=1
done
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
rm -rf "$TMP"
exit "$fail"
