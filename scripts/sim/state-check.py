#!/usr/bin/env python3
"""Validates the kw-state.json the DEBUG app writes for one screenshot hook. Exit 1 on any failure."""
import json, sys

hook, path = sys.argv[1], sys.argv[2]
mode = sys.argv[3] if len(sys.argv) > 3 else "full"   # "ready" only waits for completion
try:
    s = json.load(open(path))
except Exception as e:  # noqa: BLE001
    print(f"WAIT {hook}: no state yet ({e})"); sys.exit(2)

AUTHORIZED = {"3", "4"}  # PHAuthorizationStatus.authorized / .limited

def fail(msg):
    print(f"FAIL {hook}: {msg}\n{json.dumps(s, indent=1)}"); sys.exit(1)

if s.get("screen") != hook:
    print(f"WAIT {hook}: state is for {s.get('screen')!r}"); sys.exit(2)
if s.get("status") not in AUTHORIZED:
    fail(f"photo access status {s.get('status')!r} (want authorized=3 or limited=4)")
if s.get("ready") is not True:
    print(f"WAIT {hook}: hook not finished"); sys.exit(2)
if hook == "duplicates" and s.get("dupPhase") != "ready":
    print(f"WAIT {hook}: duplicate scan {s.get('dupPhase')!r}"); sys.exit(2)
if hook == "zoom" and not s.get("zoomScale"):
    print(f"WAIT {hook}: card not zoomed yet"); sys.exit(2)
if mode == "ready":
    print(f"READY {hook}"); sys.exit(0)

p = s.get("path", "")
checks = {
    "home": (s.get("months", 0) > 0 and p == "", "home needs months listed and no navigation"),
    "swipe": ("session(" in p and "month" in p and s.get("newestMonthCount", 0) > 0, "swipe needs a month session with items"),
    "month": ("session(" in p and "month" in p and s.get("newestMonthCount", 0) > 0, "month needs a month session with items"),
    "onthisday": ("onThisDay" in p and s.get("onThisDay", 0) > 0, "onthisday needs On this day items"),
    "screenshots": ("screenshots" in p and s.get("screenshots", 0) > 0, "screenshots needs items in the Screenshots album"),
    "duplicates": (p == "duplicates" and s.get("dupGroups", 0) > 0, "duplicates needs at least one group"),
    "tray": (p == "tray" and s.get("pending", 0) > 0, "tray needs pending items"),
    "explainer": (s.get("showExplainer") is True, "explainer sheet not shown"),
    "freed": (s.get("summaryCount", 0) > 0 and s.get("summaryBytes", 0) > 0, "freed summary needs items and bytes"),
    "paywall": (s.get("showPaywall") is True, "paywall sheet not shown"),
    "settings": (p == "settings", "settings not pushed"),
    "months": (p == "" and s.get("monthsDone", 0) >= 1 and s.get("monthsPartial", 0) >= 1,
               "months needs the month list with at least one Done and one partially reviewed month"),
    "zoom": ("session(" in p and "month" in p and 2.4 <= float(s.get("zoomScale", 0)) <= 2.6
             and s.get("zoomBlocksDecide") is True, "zoom needs the month card at about 2.5x with keep/delete blocked"),
}
if s.get("assets", 0) <= 0:
    fail("library is empty")
ok, msg = checks.get(hook, (False, f"unknown hook {hook}"))
if not ok:
    fail(msg)
print(f"OK {hook}: assets={s.get('assets')} months={s.get('months')} onThisDay={s.get('onThisDay')} "
      f"screenshots={s.get('screenshots')} dupGroups={s.get('dupGroups')} pending={s.get('pending')} path={p!r} "
      f"monthsDone={s.get('monthsDone')} monthsPartial={s.get('monthsPartial')} zoomScale={s.get('zoomScale')} "
      f"detailPixelWidth={s.get('detailPixelWidth')}")
