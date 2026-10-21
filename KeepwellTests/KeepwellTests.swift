import XCTest
import CoreGraphics
@testable import Keepwell

/// Pure-logic tests. Everything that touches PhotoKit, StoreKit or the UI is covered by the
/// Simulator screenshot job instead (see .github/workflows/sim-proof.yml).
@MainActor
final class KeepwellTests: XCTestCase {

    // MARK: Free quota resets at local midnight (Calendar.current.startOfDay)

    func testStartOfTodayUsesLocalCalendarMidnight() {
        let now = Date()
        XCTAssertEqual(CleanupStore.startOfToday(now), Calendar.current.startOfDay(for: now))
        let later = now.addingTimeInterval(3600)
        if Calendar.current.isDate(now, inSameDayAs: later) {
            XCTAssertEqual(CleanupStore.startOfToday(now), CleanupStore.startOfToday(later))
        }
    }

    func testFreeDailyLimitIsFifty() {
        XCTAssertEqual(CleanupStore.freeDailyDeleteLimit, 50)
        let store = CleanupStore()
        XCTAssertLessThanOrEqual(store.freeDeletesLeftToday, 50)
        XCTAssertGreaterThanOrEqual(store.freeDeletesLeftToday, 0)
    }

    // MARK: Swipe decisions: left = delete, right = keep, undo clears, prune drops stale ids

    func testMarkKeepUndoAndPrune() {
        let store = CleanupStore()
        let a = "test-a-\(UUID().uuidString)", b = "test-b-\(UUID().uuidString)"
        store.clearDecision(a); store.clearDecision(b)

        store.markForDeletion(a)
        XCTAssertTrue(store.isPending(a))
        XCTAssertFalse(store.kept.contains(a))

        store.keep(a)
        XCTAssertFalse(store.isPending(a))
        XCTAssertTrue(store.kept.contains(a))

        store.markForDeletion(b)
        store.clearDecision(b) // Undo
        XCTAssertFalse(store.isPending(b))
        XCTAssertFalse(store.kept.contains(b))

        store.markForDeletion(b)
        store.prune(validIDs: [a]) // b no longer exists in the library
        XCTAssertFalse(store.isPending(b))
        XCTAssertTrue(store.kept.contains(a))

        store.clearDecision(a); store.clearDecision(b)
    }

    // MARK: Explainer gate before the first delete

    func testExplainerShownBeforeFirstDeleteOnly() {
        let store = CleanupStore()
        let ids = ["x-\(UUID().uuidString)"]
        if !store.hasSeenExplainer {
            store.requestDelete(ids, isPro: true)
            XCTAssertTrue(store.showExplainer, "first delete must show the Recently Deleted explainer")
            XCTAssertEqual(store.requestedIDs, ids)
            store.cancelRequest()
            XCTAssertFalse(store.showExplainer)
            XCTAssertTrue(store.requestedIDs.isEmpty)
        } else {
            XCTAssertFalse(store.showExplainer)
        }
    }

    // MARK: Month / On this day bucketing

    func testBucketingByMonthAndOnThisDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
            cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
        }
        let now = date(2026, 10, 6)
        let infos = [
            AssetInfo(id: "n3", date: date(2026, 10, 5)),
            AssetInfo(id: "n2", date: date(2026, 10, 2)),
            AssetInfo(id: "v1", date: date(2026, 9, 20), isVideo: true),
            AssetInfo(id: "n1", date: date(2026, 9, 1)),
            AssetInfo(id: "o2", date: date(2024, 10, 6)),
            AssetInfo(id: "o1", date: date(2023, 10, 6)),
            AssetInfo(id: "u0", date: nil),
        ]
        let snap = LibrarySnapshot.bucket(newestFirst: infos, now: now, calendar: cal)

        XCTAssertEqual(snap.months.map(\.id), ["2026-10", "2026-09", "2024-10", "2023-10", "0000-00"])
        XCTAssertEqual(snap.months[0].assetIDs, ["n2", "n3"], "oldest first inside a month")
        XCTAssertEqual(snap.months[1].assetIDs, ["n1", "v1"])
        XCTAssertEqual(snap.months.last?.title, "Undated")
        XCTAssertEqual(snap.onThisDay, ["o1", "o2"], "same month/day in past years, oldest first")
        XCTAssertEqual(snap.imagesOldestFirst.map(\.id), ["u0", "o1", "o2", "n1", "n2", "n3"], "videos excluded")
        XCTAssertEqual(snap.byID.count, 7)
    }

    // MARK: Per-month saved progress

    private func month(_ id: String, _ ids: [String]) -> MonthBucket {
        MonthBucket(id: id, title: id, assetIDs: ids)
    }

    func testMonthProgressSaveRestoreRoundTrip() throws {
        var progress = MonthProgress()
        progress.markReviewed("a", in: "2026-09")
        progress.markReviewed("b", in: "2026-09")
        progress.markReviewed("z", in: "2026-08")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("progress-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try progress.save(to: url)
        let restored = MonthProgress.load(from: url)
        XCTAssertEqual(restored, progress)
        XCTAssertTrue(restored.isReviewed("b", in: "2026-09"))
        XCTAssertFalse(restored.isReviewed("z", in: "2026-09"))
        XCTAssertEqual(MonthProgress.load(from: url.appendingPathExtension("missing")), MonthProgress(),
                       "a missing file means no progress, not a crash")
    }

    func testCleanupStorePersistsMonthProgressAcrossLaunches() {
        let monthID = "test-\(UUID().uuidString)"
        let ids = (0..<3).map { "\(monthID)-\($0)" }
        let bucket = month(monthID, ids)
        let store = CleanupStore()
        store.recordReviewed(ids[0], inMonth: monthID)
        store.recordReviewed(ids[1], inMonth: monthID)

        let relaunched = CleanupStore()
        XCTAssertEqual(relaunched.monthProgress.reviewedCount(in: bucket), 2)
        XCTAssertEqual(relaunched.monthProgress.resumeIndex(in: bucket), 2)

        relaunched.clearReviewed(ids[1], inMonth: monthID) // Undo
        XCTAssertEqual(CleanupStore().monthProgress.reviewedCount(in: bucket), 1)

        relaunched.resetMonth(bucket)
        XCTAssertEqual(CleanupStore().monthProgress.reviewedCount(in: bucket), 0)
    }

    func testResumeIndexIsFirstUnreviewedPhoto() {
        let m = month("2026-09", ["p0", "p1", "p2", "p3", "p4"])
        var progress = MonthProgress()
        XCTAssertEqual(progress.resumeIndex(in: m), 0)
        progress.markReviewed("p0", in: m.id)
        progress.markReviewed("p1", in: m.id)
        progress.markReviewed("p3", in: m.id)
        XCTAssertEqual(progress.resumeIndex(in: m), 2)
        XCTAssertEqual(progress.nextUnreviewed(in: m.id, ids: m.assetIDs, from: 3), 4, "skips p3, already swiped")
        progress.markReviewed("p2", in: m.id)
        progress.markReviewed("p4", in: m.id)
        XCTAssertEqual(progress.resumeIndex(in: m), m.assetIDs.count)
        XCTAssertEqual(progress.reviewedCount(in: m), 5)
        progress.markReviewed("p0", in: "2026-08")
        XCTAssertEqual(progress.reviewedCount(in: m), 5, "other months never count")
    }

    func testDoneDetectionAndNewPhotoInvalidation() {
        var progress = MonthProgress()
        let m = month("2026-09", ["a", "b"])
        XCTAssertFalse(progress.isDone(m))
        XCTAssertFalse(progress.isDone(month("empty", [])), "an empty month is never Done")
        progress.markReviewed("a", in: m.id)
        XCTAssertFalse(progress.isDone(m))
        progress.markReviewed("b", in: m.id)
        XCTAssertTrue(progress.isDone(m))

        let grown = month("2026-09", ["a", "b", "c"]) // a photo added to the month later
        XCTAssertFalse(progress.isDone(grown))
        XCTAssertEqual(progress.reviewedCount(in: grown), 2)
        XCTAssertEqual(progress.resumeIndex(in: grown), 2, "resumes at the new photo")
    }

    func testDeletedAssetsArePrunedFromProgress() {
        var progress = MonthProgress()
        progress.markReviewed("a", in: "2026-09")
        progress.markReviewed("gone", in: "2026-09")
        progress.markReviewed("gone2", in: "2026-08")
        XCTAssertTrue(progress.prune(validIDs: ["a", "b"]))
        XCTAssertTrue(progress.isReviewed("a", in: "2026-09"))
        XCTAssertFalse(progress.isReviewed("gone", in: "2026-09"))
        XCTAssertEqual(progress.reviewed["2026-08"], nil, "a month with nothing left is dropped")
        XCTAssertFalse(progress.prune(validIDs: ["a", "b"]), "second prune is a no-op")

        // A month whose reviewed photo was deleted stays Done if every remaining photo is reviewed.
        let m = month("2026-09", ["a"])
        XCTAssertTrue(progress.isDone(m))
    }

    func testReviewAgainResetsOnlyThatMonth() {
        var progress = MonthProgress()
        let sep = month("2026-09", ["a", "b"]), aug = month("2026-08", ["c"])
        for id in sep.assetIDs { progress.markReviewed(id, in: sep.id) }
        progress.markReviewed("c", in: aug.id)
        XCTAssertTrue(progress.isDone(sep))
        progress.reset(sep.id)
        XCTAssertFalse(progress.isDone(sep))
        XCTAssertEqual(progress.resumeIndex(in: sep), 0)
        XCTAssertTrue(progress.isDone(aug))
    }

    func testCleanupStoreReviewAgainClearsKeptButLeavesTray() {
        let monthID = "test-\(UUID().uuidString)"
        let kept = "\(monthID)-kept", marked = "\(monthID)-marked"
        let bucket = month(monthID, [kept, marked])
        let store = CleanupStore()
        store.keep(kept); store.recordReviewed(kept, inMonth: monthID)
        store.markForDeletion(marked); store.recordReviewed(marked, inMonth: monthID)
        XCTAssertTrue(store.monthProgress.isDone(bucket))

        store.resetMonth(bucket)
        XCTAssertFalse(store.monthProgress.isDone(bucket))
        XCTAssertFalse(store.kept.contains(kept))
        XCTAssertTrue(store.isPending(marked), "Review again never empties the review tray")

        store.recordReviewed(kept, inMonth: monthID)
        store.prune(validIDs: [kept]) // `marked` was deleted elsewhere
        XCTAssertEqual(store.monthProgress.reviewedCount(in: month(monthID, [kept])), 1)
        XCTAssertFalse(store.monthProgress.isReviewed(marked, in: monthID))
        store.resetMonth(bucket); store.clearDecision(marked)
    }

    // MARK: Pinch-to-zoom on the swipe card

    func testSwipeCommitsAtOneX() {
        var g = CardGestureState()
        g.container = CGSize(width: 300, height: 500)
        g.dragChanged(CGSize(width: 150, height: 0))
        XCTAssertEqual(g.swipe.width, 150)
        XCTAssertEqual(g.dragEnded(translation: CGSize(width: 150, height: 0), predictedEnd: CGSize(width: 160, height: 0)), .keep)
        g.dragChanged(CGSize(width: -40, height: 0))
        XCTAssertEqual(g.dragEnded(translation: CGSize(width: -40, height: 0), predictedEnd: CGSize(width: -400, height: 0)), .delete)
        g.dragChanged(CGSize(width: 30, height: 0))
        XCTAssertNil(g.dragEnded(translation: CGSize(width: 30, height: 0), predictedEnd: CGSize(width: 40, height: 0)))
    }

    func testZoomedCardPansAndNeverCommits() {
        var g = CardGestureState()
        g.container = CGSize(width: 300, height: 500)
        g.pinchChanged(2.0)
        XCTAssertTrue(g.isZoomed)
        XCTAssertFalse(g.canDecide)
        g.pinchEnded()
        XCTAssertEqual(g.scale, 2.0, accuracy: 0.0001)
        XCTAssertTrue(g.wantsHighResolution, "past 1.5x the card asks for a detail image")

        g.dragChanged(CGSize(width: 400, height: 0))
        XCTAssertEqual(g.dragMode, .pan)
        XCTAssertEqual(g.swipe, .zero, "the card does not move while zoomed")
        XCTAssertEqual(g.offset.width, 150, accuracy: 0.0001, "pan is clamped to the overflow")
        XCTAssertNil(g.dragEnded(translation: CGSize(width: 400, height: 0), predictedEnd: CGSize(width: 900, height: 0)),
                     "a big horizontal drag while zoomed is a pan, never a keep")
        XCTAssertNil(g.dragEnded(translation: CGSize(width: -400, height: 0), predictedEnd: CGSize(width: -900, height: 0)))
    }

    func testPinchBackToOneXRestoresSwiping() {
        var g = CardGestureState()
        g.container = CGSize(width: 300, height: 500)
        g.pinchChanged(3)
        g.dragChanged(CGSize(width: 200, height: 0)) // drag that started zoomed
        g.pinchChanged(0.2)                        // pinch all the way out, clamped to 1x
        XCTAssertEqual(g.scale, 1, accuracy: 0.0001)
        g.pinchEnded()
        XCTAssertFalse(g.isZoomed)
        XCTAssertEqual(g.offset, .zero)
        XCTAssertNil(g.dragEnded(translation: CGSize(width: 200, height: 0), predictedEnd: CGSize(width: 500, height: 0)),
                     "the drag that began zoomed still cannot commit")
        XCTAssertTrue(g.canDecide)
        g.dragChanged(CGSize(width: 150, height: 0))
        XCTAssertEqual(g.dragMode, .swipe)
        XCTAssertEqual(g.dragEnded(translation: CGSize(width: 150, height: 0), predictedEnd: CGSize(width: 150, height: 0)), .keep)
    }

    func testPinchDuringSwipeBlocksCommit() {
        var g = CardGestureState()
        g.dragChanged(CGSize(width: 90, height: 0))
        g.pinchChanged(1.02)
        XCTAssertEqual(g.dragMode, .blocked)
        XCTAssertEqual(g.swipe, .zero)
        g.pinchEnded() // released below the snap-back scale
        XCTAssertEqual(g.scale, 1)
        XCTAssertNil(g.dragEnded(translation: CGSize(width: 200, height: 0), predictedEnd: CGSize(width: 400, height: 0)))
    }

    func testDoubleTapTogglesAndScaleIsClamped() {
        var g = CardGestureState()
        g.container = CGSize(width: 300, height: 500)
        g.doubleTap()
        XCTAssertEqual(g.scale, CardGestureState.doubleTapScale)
        XCTAssertEqual(g.scale, 2.5)
        XCTAssertFalse(g.canDecide)
        g.doubleTap()
        XCTAssertEqual(g.scale, 1)
        XCTAssertTrue(g.canDecide)
        g.pinchChanged(10)
        XCTAssertEqual(g.scale, CardGestureState.maxScale)
        XCTAssertEqual(g.scale, 4)
        XCTAssertEqual(CardGestureState.clampScale(.nan), 1)
        g.pinchEnded()
        g.reset()
        XCTAssertEqual(g.scale, 1)
        g.doubleTap()
        XCTAssertFalse(g.canDecide, "zoomed: Keep and Delete are disabled and dimmed")
        g.reset()
        XCTAssertTrue(g.canDecide, "reset (next card) re-enables Keep and Delete")
        XCTAssertFalse(g.isZoomed)
        XCTAssertEqual(g.container, CGSize(width: 300, height: 500), "reset keeps the measured card size")
    }

    // MARK: Duplicates: slider maps Exact..Loose to 0.05..0.75 and regroups from cached pairs

    func testSimilarityThresholdRange() {
        XCTAssertEqual(DuplicateEngine.threshold(for: 0), 0.05, accuracy: 0.0001)
        XCTAssertEqual(DuplicateEngine.threshold(for: 1), 0.75, accuracy: 0.0001)
        XCTAssertLessThan(DuplicateEngine.threshold(for: 1), DuplicateScanner.maxStoredDistance)
    }

    func testRegroupLiveWithoutRescan() {
        let engine = DuplicateEngine()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let items = (0..<4).map { i in
            AssetInfo(id: "p\(i)", date: base.addingTimeInterval(Double(i) * 60),
                      pixelWidth: 1000 + i, pixelHeight: 1000, isFavorite: i == 1)
        }
        let pairs = [
            SimilarPair(a: 0, b: 1, distance: 0.10), // near-exact
            SimilarPair(a: 1, b: 2, distance: 0.50), // only similar
            SimilarPair(a: 2, b: 3, distance: 0.85), // never grouped (above Loose)
        ]
        engine.similarity = 0.0 // Exact: threshold 0.05
        engine.loadCached(items: items, pairs: pairs)
        XCTAssertEqual(engine.phase, .ready)
        XCTAssertTrue(engine.groups.isEmpty)

        engine.similarity = 0.35 // threshold 0.295
        XCTAssertEqual(engine.groups.count, 1)
        XCTAssertEqual(Set(engine.groups[0].assetIDs), ["p0", "p1"])
        XCTAssertEqual(engine.groups[0].bestID, "p1", "favorite wins keep-best")
        XCTAssertEqual(engine.markedCount, 1)
        XCTAssertEqual(engine.allMarkedIDs, ["p0"])

        engine.similarity = 1.0 // Loose: threshold 0.75
        XCTAssertEqual(engine.groups.count, 1)
        XCTAssertEqual(Set(engine.groups[0].assetIDs), ["p0", "p1", "p2"])
        XCTAssertEqual(engine.markedCount, 2)

        engine.toggle("p1", in: engine.groups[0])
        XCTAssertTrue(engine.isMarked("p1", in: engine.groups[0]))
        XCTAssertEqual(engine.markedCount, 3)
    }

    func testKeepBestOrderFavoriteThenResolutionThenRecency() {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let fav = AssetInfo(id: "fav", date: t, pixelWidth: 100, pixelHeight: 100, isFavorite: true)
        let big = AssetInfo(id: "big", date: t, pixelWidth: 4000, pixelHeight: 3000)
        let small = AssetInfo(id: "small", date: t.addingTimeInterval(60), pixelWidth: 1000, pixelHeight: 750)
        let newer = AssetInfo(id: "newer", date: t.addingTimeInterval(60), pixelWidth: 4000, pixelHeight: 3000)
        XCTAssertGreaterThan(DuplicateEngine.score(fav), DuplicateEngine.score(big))
        XCTAssertGreaterThan(DuplicateEngine.score(big), DuplicateEngine.score(small))
        XCTAssertGreaterThan(DuplicateEngine.score(newer), DuplicateEngine.score(big))
    }

    func testDistanceSourceTrustsVisionOnlyWhenItSeparatesDifferentPhotos() {
        XCTAssertEqual(DuplicateScanner.chooseSource(hasVisionPrints: false, probeDistance: nil), .hash)
        XCTAssertEqual(DuplicateScanner.chooseSource(hasVisionPrints: true, probeDistance: nil), .vision)
        XCTAssertEqual(DuplicateScanner.chooseSource(hasVisionPrints: true, probeDistance: 0), .hash,
                       "clearly different photos at distance 0 means Vision output is degenerate")
        XCTAssertEqual(DuplicateScanner.chooseSource(hasVisionPrints: true, probeDistance: 0.0018), .hash,
                       "value observed on the iOS 26.5 Simulator for two unrelated photos")
        XCTAssertEqual(DuplicateScanner.chooseSource(hasVisionPrints: true, probeDistance: 0.62), .vision)
    }

    func testDifferenceHashFallback() throws {
        func image(_ fill: (Int, Int) -> UInt8) throws -> CGImage {
            let w = 64, h = 64
            var px = [UInt8](repeating: 0, count: w * h)
            for y in 0..<h { for x in 0..<w { px[y * w + x] = fill(x, y) } }
            let made: CGImage? = px.withUnsafeMutableBytes { buffer in
                guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
                return ctx.makeImage()
            }
            return try XCTUnwrap(made)
        }
        let gradient = try image { x, _ in UInt8(x * 4) }
        let gradientAgain = try image { x, _ in UInt8(min(255, x * 4 + 3)) }
        let reversed = try image { x, _ in UInt8(255 - x * 4) }
        let h1 = try XCTUnwrap(DuplicateScanner.differenceHash(gradient))
        let h2 = try XCTUnwrap(DuplicateScanner.differenceHash(gradientAgain))
        let h3 = try XCTUnwrap(DuplicateScanner.differenceHash(reversed))
        XCTAssertEqual(h1, h2)
        XCTAssertGreaterThan((h1 ^ h3).nonzeroBitCount, 40)
    }

    // MARK: Monetization

    func testProductIDsAndPlanOrder() {
        XCTAssertEqual(StoreManager.ProductID.all,
                       ["com.nimbuswebdesign.keepwell.pro.monthly",
                        "com.nimbuswebdesign.keepwell.pro.yearly",
                        "com.nimbuswebdesign.keepwell.pro.lifetime"])
        XCTAssertFalse(StoreManager.ProductID.all.contains { $0.contains("weekly") })
        XCTAssertEqual(PaywallView.Plan.allCases.first, .yearly, "yearly is the default plan")
        XCTAssertEqual(PaywallView.Plan.allCases.count, 3)
        XCTAssertEqual(PaywallView.Plan.lifetime.subtitle, "Pay once, keep Pro")
        XCTAssertEqual(PaywallView.Plan.yearly.debugFallbackPrice, "$14.99")
        XCTAssertEqual(PaywallView.Plan.monthly.debugFallbackPrice, "$3.99")
        XCTAssertEqual(PaywallView.Plan.lifetime.debugFallbackPrice, "$24.99")
    }

    func testStoreKitConfigurationMatchesLockedPrices() throws {
        // Keepwell.storekit sits next to project.yml; the test bundle can reach it through SRCROOT-relative lookup.
        let url = try XCTUnwrap(Bundle(for: KeepwellTests.self).url(forResource: "Keepwell", withExtension: "storekit")
                                ?? storekitURLFromSource())
        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let products = try XCTUnwrap(json["products"] as? [[String: Any]])
        XCTAssertEqual(products.first?["productID"] as? String, StoreManager.ProductID.lifetime)
        XCTAssertEqual(products.first?["displayPrice"] as? String, "24.99")
        let groups = try XCTUnwrap(json["subscriptionGroups"] as? [[String: Any]])
        let subs = try XCTUnwrap(groups.first?["subscriptions"] as? [[String: Any]])
        let prices = Dictionary(uniqueKeysWithValues: subs.map { ($0["productID"] as? String ?? "", $0["displayPrice"] as? String ?? "") })
        XCTAssertEqual(prices[StoreManager.ProductID.yearly], "14.99")
        XCTAssertEqual(prices[StoreManager.ProductID.monthly], "3.99")
        XCTAssertEqual(subs.count, 2, "no weekly plan")
        XCTAssertTrue(subs.allSatisfy { ($0["introductoryOffer"] as? NSNull) != nil || $0["introductoryOffer"] == nil }, "no trial")
    }

    private func storekitURLFromSource() -> URL? {
        // #filePath = <repo>/KeepwellTests/KeepwellTests.swift
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let url = repo.appendingPathComponent("Keepwell.storekit")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: Links and copy

    func testLinksAndFormatting() {
        XCTAssertEqual(KWLinks.privacy.absoluteString, "https://cennisgit.github.io/app-pages/apps/keepwell/privacy/")
        XCTAssertEqual(KWLinks.support.absoluteString, "https://cennisgit.github.io/app-pages/apps/keepwell/support/")
        XCTAssertEqual(KWLinks.terms.absoluteString, "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
        XCTAssertFalse(formatBytes(0).isEmpty)
        XCTAssertTrue(formatBytes(1_500_000).contains("MB"))
    }
}
