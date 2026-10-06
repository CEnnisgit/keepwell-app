import Foundation
import Photos
import UIKit
import Observation

/// Review tray, kept set, daily free-delete quota, running space-freed total and the delete flow.
@MainActor
@Observable
final class CleanupStore {
    static let freeDailyDeleteLimit = 50

    enum Keys {
        static let totalFreedBytes = "totalFreedBytes"      // also read with @AppStorage
        static let totalDeletedCount = "totalDeletedCount"
        static let hasSeenDeleteExplainer = "hasSeenDeleteExplainer"
        static let dailyDeleteDay = "dailyDeleteDay"
        static let dailyDeleteCount = "dailyDeleteCount"
    }

    /// Marked for deletion, in the order they were swiped.
    private(set) var pending: [String] = []
    private(set) var kept: Set<String> = []
    private(set) var totalFreedBytes: Int
    private(set) var totalDeletedCount: Int
    private(set) var hasSeenExplainer: Bool
    /// Start of the local day (Calendar.current.startOfDay) that `dailyCount` belongs to.
    private(set) var dailyDay: Date
    private(set) var dailyCount: Int

    // Delete flow state, observed by DeleteFlowModifier at the root.
    var requestedIDs: [String] = []
    var showExplainer = false
    var showQuotaAlert = false
    var showPaywall = false
    var isDeleting = false
    var summary: FreedSummary?
    var errorMessage: String?

    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        totalFreedBytes = defaults.integer(forKey: Keys.totalFreedBytes)
        totalDeletedCount = defaults.integer(forKey: Keys.totalDeletedCount)
        hasSeenExplainer = defaults.bool(forKey: Keys.hasSeenDeleteExplainer)
        dailyDay = defaults.object(forKey: Keys.dailyDeleteDay) as? Date ?? .distantPast
        dailyCount = defaults.integer(forKey: Keys.dailyDeleteCount)
        loadState()
    }

    // MARK: Swipe decisions

    func isPending(_ id: String) -> Bool { pending.contains(id) }

    func markForDeletion(_ id: String) {
        kept.remove(id)
        if !pending.contains(id) { pending.append(id) }
        saveState()
    }

    func keep(_ id: String) {
        pending.removeAll { $0 == id }
        kept.insert(id)
        saveState()
    }

    /// Clears any decision (used by Undo and by tapping an item in the tray).
    func clearDecision(_ id: String) {
        pending.removeAll { $0 == id }
        kept.remove(id)
        saveState()
    }

    func unmark(_ id: String) {
        pending.removeAll { $0 == id }
        saveState()
    }

    /// Drops ids that no longer exist in the library (deleted elsewhere, or deselected in limited mode).
    func prune(validIDs: Set<String>) {
        let before = (pending.count, kept.count)
        pending.removeAll { !validIDs.contains($0) }
        kept = kept.intersection(validIDs)
        if before != (pending.count, kept.count) { saveState() }
    }

    func resetKept(for ids: [String]) {
        kept.subtract(ids)
        saveState()
    }

    // MARK: Quota

    /// Local midnight for the given moment. The free counter resets when this changes.
    static func startOfToday(_ date: Date = .now) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    var freeDeletesLeftToday: Int {
        let used = dailyDay == Self.startOfToday() ? dailyCount : 0
        return max(0, Self.freeDailyDeleteLimit - used)
    }

    // MARK: Delete flow

    /// Entry point for every delete (review tray, duplicate groups).
    func requestDelete(_ ids: [String], isPro: Bool) {
        guard !ids.isEmpty, !isDeleting else { return }
        requestedIDs = ids
        if !hasSeenExplainer {
            showExplainer = true
        } else {
            proceed(isPro: isPro)
        }
    }

    func explainerAccepted(isPro: Bool) {
        hasSeenExplainer = true
        defaults.set(true, forKey: Keys.hasSeenDeleteExplainer)
        showExplainer = false
        proceed(isPro: isPro)
    }

    func cancelRequest() {
        requestedIDs = []
        showExplainer = false
        showQuotaAlert = false
    }

    func proceed(isPro: Bool) {
        if !isPro && requestedIDs.count > freeDeletesLeftToday {
            showQuotaAlert = true
            return
        }
        let ids = requestedIDs
        Task { await runDelete(ids, countsAgainstQuota: !isPro) }
    }

    /// Deletes only what today's free allowance covers.
    func deleteWithinAllowance() {
        let ids = Array(requestedIDs.prefix(freeDeletesLeftToday))
        showQuotaAlert = false
        guard !ids.isEmpty else { return }
        Task { await runDelete(ids, countsAgainstQuota: true) }
    }

    func runDelete(_ ids: [String], countsAgainstQuota: Bool) async {
        isDeleting = true
        defer { isDeleting = false; requestedIDs = [] }

        let sizes = await Task.detached(priority: .userInitiated) { AssetBytes.perAsset(for: ids) }.value
        // Thumbnails must be captured before deletion; afterwards the assets are only in Recently Deleted.
        var thumbs: [UIImage] = []
        for id in ids.prefix(60) {
            if let image = await ImageLoader.image(for: id, size: CGSize(width: 240, height: 240)) {
                thumbs.append(image)
            }
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
                PHAssetChangeRequest.deleteAssets(assets)
            }
        } catch {
            if let photosError = error as? PHPhotosError, photosError.code == .userCancelled { return }
            errorMessage = "Couldn't delete: \(error.localizedDescription)"
            return
        }

        // Count only what is actually gone now.
        let stillThere = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var remaining = Set<String>()
        for i in 0..<stillThere.count { remaining.insert(stillThere.object(at: i).localIdentifier) }
        let deleted = ids.filter { !remaining.contains($0) }
        guard !deleted.isEmpty else { return }
        let bytes = deleted.reduce(Int64(0)) { $0 + (sizes[$1] ?? 0) }

        totalFreedBytes += Int(bytes)
        totalDeletedCount += deleted.count
        defaults.set(totalFreedBytes, forKey: Keys.totalFreedBytes)
        defaults.set(totalDeletedCount, forKey: Keys.totalDeletedCount)
        if countsAgainstQuota {
            let today = Self.startOfToday()
            if dailyDay != today { dailyDay = today; dailyCount = 0 }
            dailyCount += deleted.count
            defaults.set(dailyDay, forKey: Keys.dailyDeleteDay)
            defaults.set(dailyCount, forKey: Keys.dailyDeleteCount)
        }
        let deletedSet = Set(deleted)
        pending.removeAll { deletedSet.contains($0) }
        saveState()

        summary = FreedSummary(count: deleted.count, bytes: bytes, thumbnails: thumbs, date: .now)
    }

    #if DEBUG
    /// Screenshot helper: shows the real summary screen for the given assets without deleting anything.
    func debugShowSummary(for ids: [String]) async {
        let sizes = await Task.detached { AssetBytes.perAsset(for: ids) }.value
        var thumbs: [UIImage] = []
        for id in ids {
            if let image = await ImageLoader.image(for: id, size: CGSize(width: 240, height: 240)) { thumbs.append(image) }
        }
        summary = FreedSummary(count: ids.count, bytes: sizes.values.reduce(0, +), thumbnails: thumbs, date: .now)
    }
    #endif

    // MARK: Persistence (Application Support, on-device only)

    private struct SavedState: Codable {
        var pending: [String]
        var kept: [String]
    }

    private var stateURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("review-state.json")
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        pending = state.pending
        kept = Set(state.kept)
    }

    private func saveState() {
        let state = SavedState(pending: pending, kept: Array(kept))
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }
}
