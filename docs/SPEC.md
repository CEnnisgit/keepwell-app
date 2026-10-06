# Sweep v1 build spec (App Builder, Oct 3 2026)
Source: PM score 18/25 (provisional BUILD) + App Lead adds, iOS app team chat.
Platform: iOS 17+, SwiftUI, Swift 6, PhotoKit, StoreKit 2, built from /workspace/apps/starter template (XcodeGen).
Core: swipe left = mark for deletion, right = keep, undo; batch confirm deletes via PHAssetChangeRequest.deleteAssets (goes to iOS Recently Deleted).
Differentiators v1: (1) duplicate + near-duplicate groups (Vision feature prints, on-device), keep-best suggestion; (2) "On this day" / by-month review sessions; (3) running total of space freed (persisted locally).
Rules: photos/videos only, no data collected (no analytics/network), PrivacyInfo.xcprivacy, no "speed up your phone" claims, paywall shows lifetime price, limited-library access supported.
Monetization (App Lead, 11:01 AM): free = unlimited swiping/keeping, 50 deletions per day; Pro = unlimited deletions. Plans: monthly, yearly (default, no trial), lifetime. No weekly plan.
Working name: Keepwell ("Keepwell: Photo Cleaner"), pending Growth Lead keywords + trademark check. Design tokens: design/TOKENS.md (use dark teal for small link text).
Gates: Simulator only. No Apple account, TestFlight or spend until Owner decides on account.
Duplicates: add a "How similar" slider (App Lead, 11:02 AM) mapped to the feature-print distance threshold (Exact to Loose); regroup live without rescanning (cache pairwise distances). It is a listed differentiator, so keep it prominent.
Review notes (PM, 11:03 AM): describe Pro as ongoing value: monthly cleanup sessions and new duplicates found as the library grows, not just paying to unlock delete.
Screenshots for Designer: raw Simulator captures of month swipe, How similar slider and space freed screens.
Bundle ID (Owner via Grok Bot, 11:11 AM): com.nimbuswebdesign.keepwell; product IDs com.nimbuswebdesign.keepwell.pro.{monthly,yearly,lifetime}. Display name Keepwell.
Adds (App Lead, 11:59 AM): a "Deleted photos go to Recently Deleted (30 days)" explainer shown before the first delete, and a "See exactly what you freed" summary screen after each delete batch (thumbnails, count, bytes). Both double as screenshots.
PRICES LOCKED (App Lead, 12:05 PM, overrides earlier): monthly $3.99, yearly $14.99 (default, no trial), lifetime $24.99. Also required: an in-app Settings screen with a "Keepwell Pro" entry (status, upgrade, Restore Purchases, Manage Subscription), Restore on paywall, iPhone only (TARGETED_DEVICE_FAMILY=1), zero analytics/crash/ad SDKs or network calls.
Locked (App Lead, 12:10 PM): Undo reverses swipe choices only before the delete is confirmed; after deletion, point users to Recently Deleted (30 days), with no in-app restore. The free 50-delete counter resets at local midnight (Calendar.current startOfDay).
Adds (App Lead, 12:19 PM): Screenshots session (smartAlbumScreenshots). URLs: privacy https://nimbuswebdesign.com/apps/keepwell/privacy/, support .../support/, Terms = Apple standard EULA. Paywall copy: "Settings › [your name] › Subscriptions", "Pay once, keep Pro". Large videos cut for v1.
