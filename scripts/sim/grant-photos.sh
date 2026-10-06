#!/usr/bin/env bash
# Grants Keepwell full Photos access on a booted Simulator and PROVES it by launching the app and
# reading the status it records (DEBUG kw-state.json). Tries, in order:
#   1. simctl privacy grant after a first launch (tccd has then seen the app)
#   2. simctl privacy reset + grant
#   3. a direct TCC.db row followed by a reboot of the device
# Usage: grant-photos.sh <udid> <bundle-id> <diag-dir>
set -uo pipefail
UDID="$1"; BUNDLE="$2"; DIAG="$3"
mkdir -p "$DIAG"
LOG="$DIAG/grant-photos.log"
TCC="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Library/TCC/TCC.db"

log() { echo "$*" | tee -a "$LOG"; }
dump_tcc() {
  if [ -f "$TCC" ]; then
    log "--- TCC rows for $BUNDLE ($1):"
    sqlite3 "$TCC" "select service, client, auth_value, auth_reason, flags from access where client = '$BUNDLE';" 2>&1 | tee -a "$LOG"
  else
    log "--- no TCC.db at $TCC"
  fi
}
state_file() { echo "$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null)/Documents/kw-state.json"; }

# Launches the app once and echoes the PHAuthorizationStatus raw value it recorded ("none" if nothing).
probe() {
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  local f; f=$(state_file); rm -f "$f"
  xcrun simctl launch "$UDID" "$BUNDLE" -KWScreen home >/dev/null 2>&1 || true
  local status="none" i
  for i in $(seq 1 25); do
    sleep 1
    if [ -f "$f" ]; then
      status=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status","none"))' "$f" 2>/dev/null || echo none)
      [ "$status" != "none" ] && [ "$status" != "0" ] && break
    fi
  done
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  echo "$status"
}
authorized() { [ "$1" = "3" ] || [ "$1" = "4" ]; }

log "== first launch so tccd and LaunchServices know the app"
s=$(probe); log "status after plain launch: $s"
if authorized "$s"; then log "already authorized"; exit 0; fi

log "== 1. simctl privacy grant photos"
xcrun simctl privacy "$UDID" grant photos "$BUNDLE" 2>&1 | tee -a "$LOG"
dump_tcc "after grant"
s=$(probe); log "status: $s"
if authorized "$s"; then log "OK via simctl privacy grant"; exit 0; fi

log "== 2. simctl privacy reset + grant (photos, photos-add)"
xcrun simctl privacy "$UDID" reset photos "$BUNDLE" 2>&1 | tee -a "$LOG"
xcrun simctl privacy "$UDID" grant photos "$BUNDLE" 2>&1 | tee -a "$LOG"
xcrun simctl privacy "$UDID" grant photos-add "$BUNDLE" 2>&1 | tee -a "$LOG" || true
dump_tcc "after reset+grant"
s=$(probe); log "status: $s"
if authorized "$s"; then log "OK via reset+grant"; exit 0; fi

log "== 3. direct TCC row + reboot"
if [ -f "$TCC" ]; then
  sqlite3 "$TCC" ".schema access" 2>&1 | tee -a "$LOG"
  sqlite3 "$TCC" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, indirect_object_identifier_type, indirect_object_identifier, flags, last_modified) VALUES ('kTCCServicePhotos', '$BUNDLE', 0, 2, 2, 1, 0, 'UNUSED', 0, strftime('%s','now'));" 2>&1 | tee -a "$LOG"
  dump_tcc "after direct insert"
fi
xcrun simctl shutdown "$UDID" 2>&1 | tee -a "$LOG" || true
xcrun simctl boot "$UDID" 2>&1 | tee -a "$LOG" || true
xcrun simctl bootstatus "$UDID" -b 2>&1 | tail -n 1 | tee -a "$LOG"
s=$(probe); log "status: $s"
if authorized "$s"; then log "OK via direct TCC row"; exit 0; fi

log "FAILED: Photos access still status=$s"
xcrun simctl spawn "$UDID" log show --last 10m --predicate 'process == "tccd" OR process == "Keepwell"' > "$DIAG/tccd-log.txt" 2>&1 || true
exit 1
