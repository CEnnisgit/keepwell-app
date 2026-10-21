#!/usr/bin/env bash
# Scans every Mach-O file in an .app for DEBUG-only markers (strings and symbols).
# Usage: debug-leak-scan.sh <App.app> <report> expect-none|expect-some
# expect-none (Release): fails if any marker is found.
# expect-some (Debug, positive control): fails unless the always-visible symbol markers are found,
# proving the scan can see DEBUG code at all.
set -uo pipefail
APP="$1"; REPORT="$2"; MODE="$3"
# Symbols of DEBUG-only code: the screenshot state writer, the -KWScreen hook helpers, the stand-in price table.
SYMBOLS=(KWDebugState debugFallbackPrice debugShowSummary debugHoldSwipe)
# Literals. Swift stores strings of 15 bytes or less inline in instructions, so these may be invisible
# to `strings` even in Debug; the symbols above are the reliable signal, these are best effort.
LITERALS=('kw-state.json' 'KWScreen' '$3.99' '$14.99' '$24.99')
DUMP=$(mktemp)
while IFS= read -r f; do
  if file "$f" | grep -q 'Mach-O'; then
    echo "## $f" >> "$DUMP"
    strings -a "$f" >> "$DUMP" 2>/dev/null || true
    nm -a "$f" 2>/dev/null | xcrun swift-demangle >> "$DUMP" 2>/dev/null || true
  fi
done < <(find "$APP" -type f)
found=0; sym_found=0
{
  echo "app: $APP"; echo "mode: $MODE"
  for t in "${SYMBOLS[@]}" "${LITERALS[@]}"; do
    n=$(grep -cF -- "$t" "$DUMP" || true)
    echo "$t: $n"
    [ "$n" -gt 0 ] && found=$((found + 1))
  done
  for t in KWDebugState debugFallbackPrice; do
    grep -qF -- "$t" "$DUMP" && sym_found=$((sym_found + 1))
  done
} | tee "$REPORT"
found=0; sym_found=0
for t in "${SYMBOLS[@]}" "${LITERALS[@]}"; do grep -qF -- "$t" "$DUMP" && found=$((found + 1)); done
for t in KWDebugState debugFallbackPrice; do grep -qF -- "$t" "$DUMP" && sym_found=$((sym_found + 1)); done
rm -f "$DUMP"
if [ "$MODE" = expect-none ]; then
  [ "$found" -eq 0 ] && { echo "OK: no DEBUG markers" | tee -a "$REPORT"; exit 0; }
  echo "FAIL: $found DEBUG marker(s) in the Release app" | tee -a "$REPORT"; exit 1
else
  [ "$sym_found" -eq 2 ] && { echo "OK: control sees DEBUG symbols" | tee -a "$REPORT"; exit 0; }
  echo "FAIL: control could not see DEBUG symbols; the scan is blind" | tee -a "$REPORT"; exit 1
fi
