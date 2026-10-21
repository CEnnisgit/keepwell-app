# Keepwell: App Review notes (DRAFT, not submitted)

**What Keepwell does**
Keepwell helps people clear out their camera roll in short sessions. Each photo or video appears as a card: swipe left to mark it for deletion, swipe right to keep it. Undo reverses a swipe. Nothing is deleted until the person confirms the batch in the review tray, and iOS then shows its own system confirmation. Keepwell also groups duplicate and near-duplicate photos on-device and suggests the best shot to keep. A "How similar" slider (Exact to Loose) controls how strict the grouping is.

**Photo access and privacy**
- Keepwell asks only for Photos access (photos and videos). It needs read/write access so it can delete the items the user confirms. Full and Limited access both work. With Limited access, the app shows a "Manage selection" option. If access is denied, the app shows a screen explaining how to enable it in Settings › Apps › Keepwell › Photos, with an Open Settings button.
- All processing happens on the device: thumbnails, Vision feature prints for duplicate detection, and file-size totals. Keepwell has no accounts, servers, analytics, crash reporting or ads, and it makes no network requests. The privacy manifest declares no collected data, and UserDefaults is used only for the app's own settings (reason CA92.1).
- Deletion uses `PHAssetChangeRequest.deleteAssets`. Deleted photos stay in Recently Deleted for 30 days and can be recovered from the Photos app (Albums › Recently Deleted) during that time; storage is released once they leave Recently Deleted. Keepwell's Undo only reverses swipes before a batch is confirmed; there is no in-app restore. Before the first delete, a one-time screen explains this. After each batch, a summary shows exactly what was freed.

**Keepwell Pro (ongoing value)**
The free version includes unlimited swiping and keeping, plus 50 deletions per day. Keepwell Pro removes the daily deletion cap (the free counter resets at local midnight). If a free user confirms more items than they have left, Keepwell offers to delete only what today's allowance covers or to see Pro. Pro is designed for ongoing use, not a one-off unlock:
- **Monthly cleanup sessions:** each new month appears as its own short review session, and "On this day" sessions resurface photos from the same date in past years, so there is always a small new batch to go through.
- **New duplicates as the library grows:** the duplicate and similar scan reruns whenever the library changes, so new bursts and near-identical shots are grouped as they are taken.
- **Screenshots session:** the built-in Screenshots album becomes its own swipe session, so the screenshots that pile up every week are easy to clear.
- **Running space-freed total** that keeps counting across sessions.

**Plans (auto-renewable subscriptions in one group, plus one non-consumable)**
- Keepwell Pro Monthly: `com.nimbuswebdesign.keepwell.pro.monthly`, $3.99/month
- Keepwell Pro Yearly: `com.nimbuswebdesign.keepwell.pro.yearly`, $14.99/year (default selection, no free trial)
- Keepwell Pro Lifetime: `com.nimbuswebdesign.keepwell.pro.lifetime`, $24.99 one-time (non-consumable)

There is no weekly plan, no countdown, and no fake urgency. The paywall always shows the lifetime price, has a close button visible immediately, and includes Restore Purchases, the auto-renew disclosure, Terms of Use (Apple standard EULA, https://www.apple.com/legal/internet-services/itunes/dev/stdeula/), the Privacy Policy and Support links. Fine print says "Manage or cancel anytime in Settings › [your name] › Subscriptions". Settings also has a Keepwell Pro section with Pro status, upgrade, Restore Purchases and Manage Subscription.

**How to review**
1. Launch, tap "Allow Photo Access", and choose Full or Limited access.
2. Open any month under "By month" and swipe a few cards (left = delete, right = keep). Try Undo.
3. Tap "Review" and then "Delete". The one-time Recently Deleted explainer appears, then the iOS confirmation, then the "See exactly what you freed" summary.
4. Open "Duplicates & similar" and move the "How similar" slider to watch the groups update.
5. Tap "Go Pro" (top left) or Settings › Upgrade to see the paywall. Sandbox purchases work with any sandbox account.

Privacy Policy: https://cennisgit.github.io/app-pages/apps/keepwell/privacy/
Support: https://cennisgit.github.io/app-pages/apps/keepwell/support/
