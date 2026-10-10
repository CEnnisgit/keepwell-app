import Foundation

/// Which assets have been swiped (kept or marked for deletion) in each month, keyed by `MonthBucket.id`.
/// Pure value type: CleanupStore persists it, the month list and swipe sessions read it.
struct MonthProgress: Codable, Equatable, Sendable {
    private(set) var reviewed: [String: Set<String>] = [:]

    func isReviewed(_ id: String, in monthID: String) -> Bool {
        reviewed[monthID]?.contains(id) ?? false
    }

    /// Counts only ids that are still in the month, so removed or moved photos never inflate it.
    func reviewedCount(in month: MonthBucket) -> Int {
        guard let set = reviewed[month.id], !set.isEmpty else { return 0 }
        return month.assetIDs.reduce(0) { $0 + (set.contains($1) ? 1 : 0) }
    }

    /// Every current photo in the month has been swiped. A photo added later makes the month not done.
    func isDone(_ month: MonthBucket) -> Bool {
        !month.assetIDs.isEmpty && reviewedCount(in: month) == month.assetIDs.count
    }

    /// Index of the first photo not yet swiped, or `assetIDs.count` when the month is done.
    func resumeIndex(in month: MonthBucket) -> Int {
        nextUnreviewed(in: month.id, ids: month.assetIDs, from: 0)
    }

    /// First index at or after `start` whose id has not been swiped, or `ids.count`.
    func nextUnreviewed(in monthID: String, ids: [String], from start: Int) -> Int {
        guard start < ids.count else { return ids.count }
        guard let set = reviewed[monthID], !set.isEmpty else { return max(0, start) }
        var i = max(0, start)
        while i < ids.count, set.contains(ids[i]) { i += 1 }
        return i
    }

    mutating func markReviewed(_ id: String, in monthID: String) {
        reviewed[monthID, default: []].insert(id)
    }

    mutating func clear(_ id: String, in monthID: String) {
        reviewed[monthID]?.remove(id)
        if reviewed[monthID]?.isEmpty == true { reviewed[monthID] = nil }
    }

    /// "Review again": forget everything swiped in the month.
    mutating func reset(_ monthID: String) {
        reviewed[monthID] = nil
    }

    /// Drops ids PhotoKit no longer returns (deleted, or deselected in limited mode). Returns whether anything changed.
    @discardableResult
    mutating func prune(validIDs: Set<String>) -> Bool {
        var changed = false
        for (month, ids) in reviewed {
            let kept = ids.intersection(validIDs)
            guard kept.count != ids.count else { continue }
            changed = true
            reviewed[month] = kept.isEmpty ? nil : kept
        }
        return changed
    }

    // MARK: Persistence (sorted arrays so the file is stable)

    private struct Stored: Codable {
        var version = 1
        var months: [String: [String]]
    }

    init() {}

    init(from decoder: Decoder) throws {
        let stored = try Stored(from: decoder)
        reviewed = stored.months.mapValues { Set($0) }.filter { !$0.value.isEmpty }
    }

    func encode(to encoder: Encoder) throws {
        try Stored(months: reviewed.mapValues { $0.sorted() }).encode(to: encoder)
    }

    func save(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    static func load(from url: URL) -> MonthProgress {
        guard let data = try? Data(contentsOf: url),
              let progress = try? JSONDecoder().decode(MonthProgress.self, from: data) else { return MonthProgress() }
        return progress
    }
}
