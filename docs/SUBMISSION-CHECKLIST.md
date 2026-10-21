# Keepwell App Store submission checklist

Status: **Ready** = done in this repo and checked by CI (`.github/workflows/sim-proof.yml`) or by inspection.
**Needs Owner** = a decision or an action only Owner can take. **Needs Apple account** = needs the paid
Apple Developer Program membership and App Store Connect, which nobody has yet (see LAUNCH-STEPS).

| # | Item | Value | Status | Evidence / what is left |
|---|---|---|---|---|
| 1 | Bundle ID | `com.nimbuswebdesign.keepwell` | Ready (in code) / Needs Apple account (register the App ID) | `project.yml` `PRODUCT_BUNDLE_IDENTIFIER`. The identifier must be registered in the developer portal and an app record created. |
| 2 | Display name, version | Keepwell, 1.0 (1) | Ready | `project.yml` (`CFBundleDisplayName`, `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`). |
| 3 | IAP monthly | `com.nimbuswebdesign.keepwell.pro.monthly`, $3.99/month, auto-renewable | Ready (in code) / Needs Apple account | `Keepwell.storekit`, `StoreManager.swift`; `testStoreKitConfigurationMatchesLockedPrices`. Create in App Store Connect in one subscription group. |
| 4 | IAP yearly | `com.nimbuswebdesign.keepwell.pro.yearly`, $14.99/year, default selection, **no free trial / no introductory offer** | Ready (in code) / Needs Apple account | Paywall preselects yearly (`PaywallView.swift`). Do not add an intro offer in App Store Connect. |
| 5 | IAP lifetime | `com.nimbuswebdesign.keepwell.pro.lifetime`, $24.99 non-consumable, **Family Sharing OFF** | Ready (in code) / Needs Apple account | `Keepwell.storekit` `familyShareable: false`. Family Sharing cannot be turned off once on: leave it off in App Store Connect. |
| 6 | IAP review metadata | Display names, descriptions, one review screenshot per product (paywall `10-paywall.png`) | Needs Apple account | Screenshot exists in the `keepwell-proof` artifact. |
| 7 | Privacy nutrition label | Data Not Collected | Ready (in code) / Needs Apple account (answer the questionnaire) | `PrivacyInfo.xcprivacy`: no tracking, no collected data types, UserDefaults reason CA92.1. No networking, analytics or SDKs. |
| 8 | Age rating | 4+ (all questionnaire answers "None"/"No"; no web access, no user content shared) | Needs Apple account | Answer in App Store Connect. |
| 9 | Export compliance | `ITSAppUsesNonExemptEncryption = NO` | Ready | Already in `project.yml` Info.plist properties; CI reads it back from the Release app (`proof/release-encryption-key.txt`). |
| 10 | Privacy policy URL | https://cennisgit.github.io/app-pages/apps/keepwell/privacy/ | Ready | Live; wired in the app (`Theme.swift`) and review notes. Repoint when the new brand domain exists. |
| 11 | Support URL | https://cennisgit.github.io/app-pages/apps/keepwell/support/ | Ready | Live; wired in the app. Repoint when the new brand domain exists. Support email `apps@nimbuswebdesign.com` is a placeholder (Needs Owner, see row 23). |
| 12 | Terms of Use | Apple standard EULA (https://www.apple.com/legal/internet-services/itunes/dev/stdeula/) | Ready (in app) / Needs Apple account | Linked from paywall and Settings. In App Store Connect keep the standard EULA and put the link in the description. |
| 13 | App icon | 1024x1024 PNG, no alpha | Ready | `AppIcon.appiconset/AppIcon-1024.png` is 1024x1024 RGB (no alpha channel). |
| 14 | Review notes | `docs/REVIEW-NOTES-DRAFT.md` | Ready (draft) / Needs Owner (final read, contact details) | Matches the app: swipe/undo before confirm, one-time Recently Deleted explainer, iOS system confirm, freed summary, 50 free deletes/day reset at local midnight, limited access with Manage selection, denied screen with Open Settings. |
| 15 | Copy rules | No "undo anytime", no "speeds up your phone"; "Deleted photos stay in Recently Deleted for 30 days" | Ready | Explainer, tray, summary, paywall, onboarding and `NSPhotoLibraryUsageDescription` use the canonical sentence. |
| 16 | Photos usage string | `NSPhotoLibraryUsageDescription` | Ready | `project.yml`. `PHPhotoLibraryPreventAutomaticLimitedAccessAlert` set. |
| 17 | Release build has no DEBUG code | Stand-in prices, `-KWScreen` hooks, `KWDebugState` | Ready | CI `Build Release` step: `proof/debug-scan-release.txt` (zero markers) with a Debug positive control `proof/debug-scan-control.txt`. |
| 18 | Screenshots 6.9" (1320x2868) | `keepwell-proof` artifact `proof/screens/` | Ready (raw) / Needs Owner (pick and frame for the listing) | 18 captures verified 1320x2868 by CI. |
| 19 | UI tests | Denied access, real batch delete via iOS alert | Ready | `KeepwellUITests`; `proof/ui-test.log`. |
| 20 | Limited access UI test | — | Not automated (documented) | `simctl privacy` only has grant/revoke/reset (`proof/simctl-privacy-help.txt`); there is no limited state, and the limited picker is an out-of-process system sheet. Check by hand on a device: choose "Limit Access…", confirm the Limited banner and Manage selection. |
| 21 | Signing, TestFlight, upload | — | Needs Apple account | Out of scope for this repo work. |
| 22 | Seller / Paid Apps agreement, tax, banking | — | Needs Owner | Brand, bundle ID and URLs may change before the first upload. |
| 23 | Brand, bundle ID and URLs | `com.nimbuswebdesign.keepwell`, pages on cennisgit.github.io (temporary), `apps@nimbuswebdesign.com` | Needs Owner | Brand, bundle ID and URLs may change before the first upload. Kept as-is for now. The bundle ID (and IAP product IDs) are locked once a build is uploaded, so decide before the first upload; changing them means editing `project.yml`, `Keepwell.storekit`, `StoreManager.swift`, `Theme.swift` URLs and the tests. |
