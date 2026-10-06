# SPEC.md checklist (Simulator proof)

Status key: **Done** = implemented and shown by a Simulator screenshot or a passing unit test in the
`keepwell-proof` artifact of `.github/workflows/sim-proof.yml`. **Partial** = implemented, but only part
of it is provable here. **Not verifiable in Simulator** = implemented, but the proof needs a device,
an Apple account, or something the Simulator cannot do.

Screenshots are `proof/screens/NN-<hook>.png` (1320x2868, iPhone 17 Pro Max). Each one is paired with
`proof/state/NN-<hook>.json`, written by the DEBUG app (`Keepwell/App/DebugState.swift`) and checked by
`scripts/sim/state-check.py`: the job fails unless Photos access is authorized, the library is non-empty and the
hook reached its screen with content (months listed, On this day items, screenshots, duplicate groups, tray items,
summary bytes, sheets shown). Tests are in `KeepwellTests/KeepwellTests.swift`; their result is in `proof/test.log`.

| # | SPEC.md requirement | Status | Implementation (file:line) | Proof |
|---|---|---|---|---|
| 1 | iOS 17+, SwiftUI, Swift 6, PhotoKit, StoreKit 2, XcodeGen project | Done | `project.yml:5` (iOS 17.0), `project.yml:9` (SWIFT_VERSION 6.0), `project.yml:46` (SWIFT_STRICT_CONCURRENCY complete) | `build.log` (`** BUILD SUCCEEDED **`, zero `error:` lines), `device.txt` |
| 2 | Swipe left = mark for deletion, right = keep | Done | `Keepwell/Views/SwipeSessionView.swift:148-151` (gesture), `Keepwell/Services/CleanupStore.swift:54` (`markForDeletion`), `:60` (`keep`) | `03-month.png`, `02-swipe.png` (card held mid-swipe, Keep stamp); `testMarkKeepUndoAndPrune` |
| 3 | Undo | Done | `Keepwell/Views/SwipeSessionView.swift:181` (`undo`), `Keepwell/Services/CleanupStore.swift:67` (`clearDecision`) | Undo button in `03-month.png`; `testMarkKeepUndoAndPrune` |
| 4 | Batch confirm delete via `PHAssetChangeRequest.deleteAssets` (to Recently Deleted) | Partial | `Keepwell/Services/CleanupStore.swift:160-162` | `07-tray.png` shows the batch and the Delete button. The iOS system confirmation dialog and the real deletion are not exercised by the job: the `freed` hook renders the summary without deleting (`CleanupStore.swift:198`). The delete itself needs a manual run. |
| 5 | Duplicate + near-duplicate groups, Vision feature prints, on-device | Partial | `Keepwell/Services/DuplicateEngine.swift:64` (`VNGenerateImageFeaturePrintRequest`, revision 2), `:33` (15-minute buckets), `:106` (dHash fallback) | `06-duplicates.png` shows real groups from the seeded bursts. The screenshot cannot show whether Vision or the dHash fallback produced the distances on this Simulator; the fallback path is tested by `testDifferenceHashFallback`. |
| 6 | Keep-best suggestion | Done | `Keepwell/Services/DuplicateEngine.swift:245` (`score`: favorite, resolution, recency), `Keepwell/Views/DuplicatesView.swift:125` (BEST badge) | `06-duplicates.png` (BEST badge, extras outlined for deletion); `testKeepBestOrderFavoriteThenResolutionThenRecency`, `testRegroupLiveWithoutRescan` |
| 7 | "How similar" slider, Exact to Loose, mapped to feature-print distance, regroups live without rescan (cached distances) | Done | `Keepwell/Services/DuplicateEngine.swift:148` (`threshold`: 0.05 to 0.75), `:139` (`didSet` regroups), `:220` (`regroup` over cached pairs), `Keepwell/Views/DuplicatesView.swift:53` (slider) | `06-duplicates.png` (slider at the top of the screen, prominent); `testSimilarityThresholdRange`, `testRegroupLiveWithoutRescan` |
| 8 | "On this day" review session | Done | `Keepwell/Services/PhotoLibrary.swift:48` (same month/day, other years), `Keepwell/Views/HomeView.swift:122` | `04-onthisday.png` (seeded photos from the same date in 2022 to 2024); `testBucketingByMonthAndOnThisDay` |
| 9 | By-month review sessions | Done | `Keepwell/Services/PhotoLibrary.swift:27` (`bucket`), `Keepwell/Views/HomeView.swift:163` | `01-home.png` (BY MONTH list), `03-month.png`; `testBucketingByMonthAndOnThisDay` |
| 10 | Screenshots session (`smartAlbumScreenshots`) | Done | `Keepwell/Services/PhotoLibrary.swift:77`, `Keepwell/Views/HomeView.swift:131` | `05-screenshots.png` (seeded PNGs tagged like iOS screenshots). If the album were empty the screen would read "Nothing here"; the job does not fail on that, so check the PNG. |
| 11 | Running total of space freed, persisted locally | Partial | `Keepwell/Services/CleanupStore.swift:178` (sum of `PHAssetResource` sizes into `UserDefaults`), `Keepwell/Views/HomeView.swift:64-69` | `01-home.png` shows the SPACE FREED card; it reads Zero KB because nothing is deleted in the job. `09-freed.png` shows the per-batch bytes computed from the real asset resources. Growth of the total after a real delete needs a manual run. |
| 12 | Photos/videos only | Done | `Keepwell/Services/PhotoLibrary.swift:71-73` (fetch predicate: image or video) | `01-home.png`; `testBucketingByMonthAndOnThisDay` (videos stay out of the duplicate scan list). The seeded library has photos only; videos are display-only in v1 ("Large videos cut"). |
| 13 | No data collected: no analytics, no network | Done | No `URLSession`, `Network`, analytics or crash SDK in `Keepwell/` (grep is clean); `project.yml` has no dependencies | `build.log` links only system frameworks. Static evidence only; the Simulator job does not sniff traffic. |
| 14 | `PrivacyInfo.xcprivacy` | Done | `Keepwell/Resources/PrivacyInfo.xcprivacy:5-16` (no tracking, no collected data, UserDefaults reason CA92.1) | Bundled by the build (`build.log`) |
| 15 | No "speed up your phone" claims | Done | grep of `Keepwell/` for "speed", "faster" finds nothing | `10-paywall.png` copy |
| 16 | Paywall shows the lifetime price | Done | `Keepwell/Views/PaywallView.swift:11` (lifetime second, visible without scrolling), `:167` ("one-time") | `10-paywall.png` ($24.99 one-time) |
| 17 | Limited-library access supported (banner, Manage selection, suppressed auto prompt) | Partial | `Keepwell/Views/HomeView.swift:88-95`, `Keepwell/Services/PhotoLibrary.swift:185` (`presentLimitedLibraryPicker`), `project.yml:36` | Only full access is granted in the job (`simctl privacy grant photos`), so the banner and picker are not in any screenshot. Code path only. |
| 18 | Denied access screen linking to iOS Settings | Not verifiable in Simulator | `Keepwell/Views/RootView.swift:77-94` | The job grants access before launch; a denied-state screenshot would need a second install/launch cycle without the grant. Not captured. |
| 19 | Free = unlimited swiping/keeping, 50 deletions per day; Pro = unlimited | Partial | `Keepwell/Services/CleanupStore.swift:10` (limit 50), `:99` (left today), `:130` (quota check), `Keepwell/Views/DeleteFlow.swift:25` (quota alert) | `01-home.png` ("50 of 50 free deletes left today"), `11-settings.png`; `testFreeDailyLimitIsFifty`. Hitting the cap needs 50 real deletes, not done here. |
| 20 | Counter resets at local midnight (`Calendar.current.startOfDay`) | Done | `Keepwell/Services/CleanupStore.swift:94` (`startOfToday`), `:183-184` | `testStartOfTodayUsesLocalCalendarMidnight` |
| 21 | Plans: monthly $3.99, yearly $14.99 (default, no trial), lifetime $24.99; no weekly | Done | `Keepwell.storekit:16,46,68`, `Keepwell/Services/StoreManager.swift:9-11`, `Keepwell/Views/PaywallView.swift:8` (yearly default) | `10-paywall.png` (yearly preselected, DEBUG stand-in prices that mirror the StoreKit file); `testProductIDsAndPlanOrder`, `testStoreKitConfigurationMatchesLockedPrices` |
| 22 | Real StoreKit prices and purchase flow | Not verifiable in Simulator | `Keepwell/Services/StoreManager.swift:51` (`Product.products`), `:70` (`purchase`) | `simctl launch` does not load `Keepwell.storekit` (only Xcode's Run action does), so the paywall shows the DEBUG stand-in prices. Sandbox purchases need an Apple account, which is out of scope. |
| 23 | Bundle ID `com.nimbuswebdesign.keepwell`, product IDs `.pro.{monthly,yearly,lifetime}`, display name Keepwell | Done | `project.yml:40`, `project.yml:25`, `Keepwell/Services/StoreManager.swift:9-11` | `build.log`, `11-settings.png` title bar; `testProductIDsAndPlanOrder` |
| 24 | Design tokens from design/TOKENS.md, dark teal for small link text | Done | `Keepwell/Resources/Assets.xcassets/*.colorset`, `Keepwell/App/Theme.swift:6` (`kwBrandTealText`), used in `PaywallView.swift:202`, `SettingsView.swift:76` | `10-paywall.png` (teal links under the plans), `01-home.png` |
| 25 | Simulator only, no Apple account / TestFlight / spend | Done | Workflow builds with `CODE_SIGNING_ALLOWED=NO`; no signing files in the repo | `.github/workflows/sim-proof.yml`, `build.log` |
| 26 | Pro described as ongoing value (monthly sessions, new duplicates as the library grows) | Done | `Keepwell/Views/PaywallView.swift:115-122` (benefit rows), `docs/REVIEW-NOTES-DRAFT.md` | `10-paywall.png` |
| 27 | Raw Simulator captures of month swipe, How-similar slider and space-freed screens | Done | `scripts/sim/capture.sh`, hooks in `Keepwell/Views/HomeView.swift:188-228` | `02-swipe.png`, `03-month.png`, `06-duplicates.png`, `09-freed.png` |
| 28 | "Deleted photos go to Recently Deleted (30 days)" explainer before the first delete | Done | `Keepwell/Services/CleanupStore.swift:110`, `Keepwell/Views/DeleteFlow.swift:11,59` | `08-explainer.png`; `testExplainerShownBeforeFirstDeleteOnly` |
| 29 | "See exactly what you freed" summary after each batch (thumbnails, count, bytes) | Done | `Keepwell/Services/CleanupStore.swift:193`, `Keepwell/Views/DeleteFlow.swift:94-107` | `09-freed.png` (rendered from the newest month's first 9 items without deleting) |
| 30 | Settings screen with Keepwell Pro entry: status, upgrade, Restore Purchases, Manage Subscription | Done | `Keepwell/Views/SettingsView.swift:14-40`, `:80` (`manageSubscriptionsSheet`) | `11-settings.png` |
| 31 | Restore on paywall | Done | `Keepwell/Views/PaywallView.swift:192` | `10-paywall.png`. `AppStore.sync()` itself needs a real App Store account. |
| 32 | iPhone only (`TARGETED_DEVICE_FAMILY=1`) | Done | `project.yml:47` | `build.log` |
| 33 | Undo only before confirm; after deletion point to Recently Deleted, no in-app restore | Done | `Keepwell/Views/DeleteFlow.swift:62,125`, `Keepwell/Views/ReviewTrayView.swift:62` | `08-explainer.png`, `09-freed.png`, `07-tray.png` footer copy |
| 34 | URLs: privacy, support, Terms = Apple standard EULA | Done | `Keepwell/App/Theme.swift:33-38` | `10-paywall.png`, `11-settings.png` (About section); `testLinksAndFormatting` |
| 35 | Paywall copy: "Settings › [your name] › Subscriptions", "Pay once, keep Pro" | Done | `Keepwell/Views/PaywallView.swift:184`, `:26` | `10-paywall.png` |
| 36 | Large videos cut for v1 | Done | No video-specific flow; videos appear as cards with a duration badge (`Keepwell/Views/SwipeSessionView.swift:98-100`) | Not in a screenshot: the seeded library has no videos. |
| 37 | Working name "Keepwell: Photo Cleaner", keywords and trademark check | Not verifiable in Simulator | `project.yml:25` (display name Keepwell) | App Store metadata is outside the build. |

## Partial or not verifiable, in short
- **Real deletion (4, 11, 19):** the job never deletes, so the iOS confirmation, the space-freed total growing and the 50/day cap are shown by code and tests only. The `freed` hook renders the summary without deleting.
- **Vision vs. fallback (5):** the duplicate screenshot proves grouping, not which distance source the Simulator used.
- **Limited and denied access (17, 18):** the job grants full access once; the limited banner, the picker and the denied screen are not captured.
- **StoreKit (22, 31):** `simctl launch` cannot load the local StoreKit configuration, so prices are the DEBUG stand-ins and purchase/restore cannot be exercised.
- **Network silence (13):** shown by code inspection, not by traffic capture.
- **Store metadata (37):** outside the repo.
