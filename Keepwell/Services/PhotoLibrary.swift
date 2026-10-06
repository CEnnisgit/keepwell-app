import Foundation
import Photos
import PhotosUI
import UIKit
import Observation

/// Forwards PhotoKit change notifications (delivered on a background queue).
final class LibraryObserver: NSObject, PHPhotoLibraryChangeObserver, Sendable {
    private let onChange: @Sendable () -> Void
    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        super.init()
        PHPhotoLibrary.shared().register(self)
    }
    func photoLibraryDidChange(_ changeInstance: PHChange) { onChange() }
}

struct LibrarySnapshot: Sendable {
    var months: [MonthBucket] = []
    var byID: [String: AssetInfo] = [:]
    var imagesOldestFirst: [AssetInfo] = []
    var onThisDay: [String] = []
    var screenshots: [String] = []

    static func load(now: Date = .now) -> LibrarySnapshot {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                        PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        let cal = Calendar.current
        let today = cal.dateComponents([.year, .month, .day], from: now)

        var snap = LibrarySnapshot()
        var monthOrder: [String] = []
        var monthIDs: [String: [String]] = [:]
        var monthTitles: [String: String] = [:]
        var images: [AssetInfo] = []
        var onThisDay: [String] = []

        for i in 0..<result.count {
            let info = AssetInfo(result.object(at: i))
            snap.byID[info.id] = info
            if !info.isVideo { images.append(info) }
            let key: String
            if let date = info.date {
                let c = cal.dateComponents([.year, .month, .day], from: date)
                key = String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
                if monthTitles[key] == nil {
                    monthTitles[key] = date.formatted(.dateTime.month(.wide).year())
                }
                if c.month == today.month, c.day == today.day, c.year != today.year {
                    onThisDay.append(info.id)
                }
            } else {
                key = "0000-00"
                monthTitles[key] = "Undated"
            }
            if monthIDs[key] == nil { monthOrder.append(key); monthIDs[key] = [] }
            monthIDs[key]?.append(info.id)
        }
        snap.months = monthOrder.map { key in
            MonthBucket(id: key, title: monthTitles[key] ?? key, assetIDs: (monthIDs[key] ?? []).reversed())
        }
        snap.imagesOldestFirst = images.reversed()
        snap.onThisDay = onThisDay.reversed()

        // Built-in Screenshots smart album, oldest first.
        let albums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil)
        if let album = albums.firstObject {
            let shotOptions = PHFetchOptions()
            shotOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let shots = PHAsset.fetchAssets(in: album, options: shotOptions)
            for i in 0..<shots.count { snap.screenshots.append(shots.object(at: i).localIdentifier) }
        }
        return snap
    }
}

@MainActor
@Observable
final class PhotoLibrary {
    var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    var months: [MonthBucket] = []
    var byID: [String: AssetInfo] = [:]
    var imagesOldestFirst: [AssetInfo] = []
    var onThisDay: [String] = []
    var screenshots: [String] = []
    var isLoading = false
    var hasLoaded = false
    /// Bumped on every reload so dependent views can refresh.
    var generation = 0

    @ObservationIgnored private var observer: LibraryObserver?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    var hasAccess: Bool { status == .authorized || status == .limited }
    var isLimited: Bool { status == .limited }
    var totalCount: Int { byID.count }

    init() {
        if hasAccess { startObserving() }
    }

    func requestAccess() async {
        let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        status = newStatus
        if hasAccess {
            startObserving()
            await reload()
        }
    }

    func refreshStatus() {
        let newStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let changed = newStatus != status
        status = newStatus
        if hasAccess {
            startObserving()
            if changed || !hasLoaded { scheduleReload() }
        }
    }

    func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await reload()
        }
    }

    func reload() async {
        guard hasAccess else { return }
        isLoading = true
        let snap = await Task.detached(priority: .userInitiated) { LibrarySnapshot.load() }.value
        months = snap.months
        byID = snap.byID
        imagesOldestFirst = snap.imagesOldestFirst
        onThisDay = snap.onThisDay
        screenshots = snap.screenshots
        isLoading = false
        hasLoaded = true
        generation += 1
    }

    func ids(for session: ReviewSession) -> [String] {
        switch session {
        case .month(let key): return months.first { $0.id == key }?.assetIDs ?? []
        case .onThisDay: return onThisDay
        case .screenshots: return screenshots
        }
    }

    func title(for session: ReviewSession) -> String {
        switch session {
        case .month(let key): return months.first { $0.id == key }?.title ?? "Month"
        case .onThisDay: return "On this day"
        case .screenshots: return "Screenshots"
        }
    }

    private func startObserving() {
        guard observer == nil else { return }
        observer = LibraryObserver { [weak self] in
            Task { @MainActor in self?.scheduleReload() }
        }
    }

    /// Lets people with limited access add or remove photos from Keepwell's selection.
    func presentLimitedPicker() {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }
}
