#!/usr/bin/env bash
# Launches every DEBUG screenshot hook and captures a Simulator screenshot once the screen settles.
# Usage: capture.sh <udid> <out-dir>
set -euo pipefail
UDID="$1"; OUT="$2"
BUNDLE="com.nimbuswebdesign.keepwell"
HOOKS=(home swipe month onthisday screenshots duplicates tray explainer freed paywall settings)
mkdir -p "$OUT"
TMP=$(mktemp -d)

settle_and_capture() {
  # Screenshots until two consecutive captures are byte-identical (the status bar clock is frozen),
  # so loading thumbnails, spinners and the duplicate scan are given time to finish.
  local target="$1" min_wait="$2" max_wait="$3"
  sleep "$min_wait"
  local prev="$TMP/prev.png" cur="$TMP/cur.png" waited="$min_wait"
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

i=0
for hook in "${HOOKS[@]}"; do
  i=$((i + 1))
  file=$(printf "%s/%02d-%s.png" "$OUT" "$i" "$hook")
  echo "== $hook -> $file"
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  sleep 1
  xcrun simctl launch "$UDID" "$BUNDLE" -KWScreen "$hook"
  case "$hook" in
    duplicates) settle_and_capture "$file" 8 90 ;;
    home)       settle_and_capture "$file" 8 45 ;;
    *)          settle_and_capture "$file" 6 45 ;;
  esac
done
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
rm -rf "$TMP"
