#!/usr/bin/env bash
# Grants Keepwell full Photos access on a booted Simulator and PROVES it by launching the app and
# reading the status it records (DEBUG kw-state.json).
#
# Why not just `simctl privacy grant photos`: on iOS 26 runtimes it writes a TCC row with
# auth_version 1, but PhotoKit's read/write authorization query is a version-2 request, which tccd
# answers "unknown" (observed: AUTHREQ_RESULT authValue=1 authVersion=2 for the app, while the
# legacy query right after gets authValue=2 authVersion=1). Bumping the row to auth_version 2 and
# restarting the device makes PHPhotoLibrary.authorizationStatus(for: .readWrite) report authorized.
#
# Usage: grant-photos.sh <udid> <bundle-id> <diag-dir>
set -uo pipefail
UDID="$1"; BUNDLE="$2"; DIAG="$3"
mkdir -p "$DIAG"
LOG="$DIAG/grant-photos.log"
TCC="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Library/TCC/TCC.db"

log() { echo "$*" | tee -a "$LOG"; }
dump_tcc() {
  if [ -f "$TCC" ]; then
    log "--- TCC rows for $BUNDLE ($1): service|client|auth_value|auth_reason|auth_version|flags"
    sqlite3 "$TCC" "select service, client, auth_value, auth_reason, auth_version, flags from access where client = '$BUNDLE';" 2>&1 | tee -a "$LOG"
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
  for i in $(seq 1 15); do
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
reboot_device() {
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  xcrun simctl boot "$UDID" 2>&1 | tee -a "$LOG" || true
  xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
}
bump_version() {
  [ -f "$TCC" ] || { log "no TCC.db to update"; return 1; }
  sqlite3 "$TCC" "UPDATE access SET auth_value = 2, auth_version = 2, auth_reason = 2, last_modified = strftime('%s','now') WHERE client = '$BUNDLE' AND service = 'kTCCServicePhotos';" 2>&1 | tee -a "$LOG"
}

log "== A. simctl privacy grant photos, then auth_version 2 + reboot"
xcrun simctl privacy "$UDID" grant photos "$BUNDLE" 2>&1 | tee -a "$LOG"
dump_tcc "after simctl grant"
bump_version
dump_tcc "after auth_version bump"
reboot_device
s=$(probe); log "status: $s"
if authorized "$s"; then log "OK: Photos access authorized (status $s)"; exit 0; fi

log "== B. reset, grant again, insert a version-2 row directly, reboot"
xcrun simctl privacy "$UDID" reset photos "$BUNDLE" 2>&1 | tee -a "$LOG"
xcrun simctl privacy "$UDID" grant photos "$BUNDLE" 2>&1 | tee -a "$LOG"
if [ -f "$TCC" ]; then
  sqlite3 "$TCC" "DELETE FROM access WHERE client = '$BUNDLE' AND service = 'kTCCServicePhotos';" 2>&1 | tee -a "$LOG"
  sqlite3 "$TCC" "INSERT INTO access (service, client, client_type, auth_value, auth_reason, auth_version, indirect_object_identifier_type, indirect_object_identifier, flags, last_modified) VALUES ('kTCCServicePhotos', '$BUNDLE', 0, 2, 2, 2, 0, 'UNUSED', 0, strftime('%s','now'));" 2>&1 | tee -a "$LOG"
  sqlite3 "$TCC" ".schema access" >> "$LOG" 2>&1
fi
dump_tcc "after direct version-2 row"
reboot_device
s=$(probe); log "status: $s"
if authorized "$s"; then log "OK: Photos access authorized (status $s) via direct row"; exit 0; fi

log "FAILED: Photos access still status=$s"
xcrun simctl spawn "$UDID" log show --last 10m --predicate 'process == "tccd" OR process == "Keepwell" OR process == "assetsd"' > "$DIAG/tccd-log.txt" 2>&1 || true
exit 1
