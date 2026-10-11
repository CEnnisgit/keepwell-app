# Keepwell (codename Sweep), iOS app v1

SwiftUI photo cleaner for iOS 17+, built with Swift 6 (strict concurrency), PhotoKit, Vision and StoreKit 2.
Bundle ID `com.nimbuswebdesign.keepwell`, display name **Keepwell**, iPhone only.

## Layout
- `project.yml`: XcodeGen spec. It generates `Keepwell.xcodeproj` and `Keepwell/Info.plist`.
- `Keepwell.storekit`: local StoreKit config, attached to the `Keepwell` scheme's Run action. Prices: monthly $3.99, yearly $14.99 (no trial), lifetime $24.99.
- `Keepwell/App`: app entry point and design tokens (`Theme.swift`).
- `Keepwell/Models`: Sendable value types.
- `Keepwell/Services`: `PhotoLibrary` (auth, fetch, months, On this day), `CleanupStore` (review tray, kept set, 50/day free quota, space-freed total, delete flow), `DuplicateEngine` (Vision feature prints, cached distances, How-similar regrouping), `StoreManager` (StoreKit 2), `ImageLoader`/`AssetBytes`.
- `Keepwell/Views`: screens.
- `Keepwell/Resources`: asset catalog (icon plus color sets from design/TOKENS.md) and `PrivacyInfo.xcprivacy`.

## Build (Mac, no signing)
```bash
brew install xcodegen          # once
cd ~/Developer/Keepwell
xcodegen generate
xcodebuild -scheme Keepwell -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

## Run in the Simulator
```bash
UDID=<simulator udid>; xcrun simctl boot $UDID; open -a Simulator
xcrun simctl install $UDID build/Build/Products/Debug-iphonesimulator/Keepwell.app
xcrun simctl privacy $UDID grant photos com.nimbuswebdesign.keepwell
xcrun simctl addmedia $UDID ~/some/photos/*.jpg
xcrun simctl launch $UDID com.nimbuswebdesign.keepwell
```
To test purchases against `Keepwell.storekit`, open `Keepwell.xcodeproj` in Xcode and press Run. The StoreKit config only loads when Xcode launches the app. When the app is launched with `simctl`, DEBUG builds show the planned prices on the paywall as a stand-in, and the purchase button reports that prices aren't available.

### Screenshot hooks (DEBUG builds only)
`xcrun simctl launch $UDID com.nimbuswebdesign.keepwell -KWScreen <screen>`, where `<screen>` is one of
`home`, `swipe`, `month`, `onthisday`, `screenshots`, `duplicates`, `tray`, `explainer`, `freed`, `paywall`, `settings`, `months` or `zoom`.
`swipe` opens the newest month with the top card held mid-swipe so the Keep stamp shows. `tray` marks the newest month's first 6 items.
`freed` shows the real summary screen for the newest month's first 9 items **without deleting anything**.
`months` saves progress for the newest month (half reviewed) and the next one (Done) and scrolls to the month list; it writes
real saved progress, so the proof job runs it last. `zoom` opens the newest month with the top card at 2.5x.

## Tests and CI proof
`KeepwellTests` (XCTest, runs in the Simulator) covers the pure logic: month / On this day bucketing, swipe decisions and pruning,
the midnight quota reset, the How-similar threshold and live regrouping, keep-best order, the dHash fallback, product IDs and locked prices,
per-month saved progress (save/restore, resume, Done, new photos, pruning, Review again) and the swipe card's zoom gesture rules.
```bash
xcodebuild test -scheme Keepwell -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' CODE_SIGNING_ALLOWED=NO
```
`.github/workflows/sim-proof.yml` (branches `feat/sim-build` and `feat/month-progress-zoom`, or manual) builds, tests, seeds a generated photo library
(`scripts/sim/gen-media.swift`), drives every hook above and uploads `build.log`, `test.log`, `device.txt`, `sizes.txt` and the
1320x2868 screenshots as the `keepwell-proof` artifact. `docs/SPEC-CHECKLIST.md` maps each SPEC.md requirement to code and proof.

## Behaviour notes
- Sessions: by month, On this day, and Screenshots (the built-in `.smartAlbumScreenshots` album).
- Swipe left marks an item for deletion, swipe right keeps it, and Undo reverses swipes. Nothing is deleted until you confirm in the review tray (or in a duplicate group). iOS then shows its own confirmation, and items go to Recently Deleted for 30 days. Keepwell has no in-app restore after a delete.
- A one-time explainer appears before the first delete. After each batch, a "See exactly what you freed" summary shows thumbnails, the item count and the bytes freed.
- Free plan: unlimited swiping and keeping, plus 50 deletions per local day. The count is stored together with `Calendar.current.startOfDay` and resets at local midnight. Pro removes the cap.
- The space-freed total is the sum of `PHAssetResource` file sizes, stored in UserDefaults/`@AppStorage` (`totalFreedBytes`).
- Duplicates: Vision `VNGenerateImageFeaturePrintRequest` (revision 2) runs on photos taken within 15 minutes of each other. Pairwise distances are cached, so the How-similar slider (Exact to Loose, distance 0.05 to 0.75) regroups live without a rescan. A 64-bit dHash is the fallback when Vision fails, and also when Vision puts two clearly different photos (16 or more dHash bits apart) closer than 0.05, the tightest slider setting. The iOS 26.5 Simulator does this: it rated two unrelated photos 0.0018 apart. Keep-best order: favorite first, then highest resolution, then most recent.
- Limited access: a banner plus Settings both offer **Manage selection**, which opens `presentLimitedLibraryPicker`. The automatic limited-access prompt is suppressed. Denied access shows a screen that links to iOS Settings.
- No network calls, analytics, crash reporting or ad SDKs. No third-party dependencies.
