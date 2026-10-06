import Foundation
import Photos
import UIKit
import Vision
import Observation

struct SimilarPair: Sendable {
    let a: Int
    let b: Int
    let distance: Float
}

/// On-device scan: Vision feature prints compared only within time buckets (photos taken close together).
enum DuplicateScanner {
    /// Photos further apart than this are never compared.
    static let bucketWindow: TimeInterval = 15 * 60
    static let maxNeighbors = 40
    /// Pairs above this distance are discarded; the loosest slider setting stays below it.
    static let maxStoredDistance: Float = 0.9

    static func run(items: [AssetInfo], progress: @Sendable (Int, Int) -> Void) -> [SimilarPair] {
        let total = items.count
        guard total > 1 else { return [] }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: items.map(\.id), options: nil)
        var assetByID: [String: PHAsset] = [:]
        for i in 0..<assets.count { let a = assets.object(at: i); assetByID[a.localIdentifier] = a }

        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false

        var prints = [VNFeaturePrintObservation?](repeating: nil, count: total)
        var hashes = [UInt64?](repeating: nil, count: total)
        for (index, item) in items.enumerated() {
            autoreleasepool {
                guard let asset = assetByID[item.id] else { return }
                var cgImage: CGImage?
                manager.requestImage(for: asset, targetSize: CGSize(width: 384, height: 384),
                                     contentMode: .aspectFit, options: options) { image, _ in
                    cgImage = image?.cgImage
                }
                guard let cgImage else { return }
                hashes[index] = differenceHash(cgImage)
                let request = VNGenerateImageFeaturePrintRequest()
                request.revision = VNGenerateImageFeaturePrintRequestRevision2
                request.imageCropAndScaleOption = .scaleFill
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                if (try? handler.perform([request])) != nil {
                    prints[index] = request.results?.first
                }
            }
            if index % 10 == 0 || index == total - 1 { progress(index + 1, total) }
        }

        var pairs: [SimilarPair] = []
        for i in 0..<total {
            guard let di = items[i].date else { continue }
            var j = i + 1
            var neighbors = 0
            while j < total, neighbors < maxNeighbors {
                guard let dj = items[j].date, dj.timeIntervalSince(di) <= bucketWindow else { break }
                neighbors += 1
                if let d = distance(prints[i], prints[j], hashes[i], hashes[j]), d <= maxStoredDistance {
                    pairs.append(SimilarPair(a: i, b: j, distance: d))
                }
                j += 1
            }
        }
        return pairs
    }

    private static func distance(_ p1: VNFeaturePrintObservation?, _ p2: VNFeaturePrintObservation?,
                                 _ h1: UInt64?, _ h2: UInt64?) -> Float? {
        if let p1, let p2 {
            var d: Float = 0
            if (try? p1.computeDistance(&d, to: p2)) != nil { return d }
        }
        // Fallback when Vision is unavailable (e.g. some Simulator configurations): perceptual hash.
        if let h1, let h2 {
            return Float((h1 ^ h2).nonzeroBitCount) / 64.0 * 2.0
        }
        return nil
    }

    /// 64-bit difference hash from a 9x8 grayscale downsample.
    static func differenceHash(_ image: CGImage) -> UInt64? {
        let width = 9, height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        let ok = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        var hash: UInt64 = 0
        var bit: UInt64 = 0
        for y in 0..<height {
            for x in 0..<(width - 1) {
                if pixels[y * width + x] > pixels[y * width + x + 1] { hash |= (1 << bit) }
                bit += 1
            }
        }
        return hash
    }
}

@MainActor
@Observable
final class DuplicateEngine {
    enum Phase: Equatable {
        case idle
        case scanning(done: Int, total: Int)
        case ready
    }

    private(set) var phase: Phase = .idle
    private(set) var groups: [DuplicateGroup] = []
    /// 0 = Exact, 1 = Loose. Regrouping uses cached pairwise distances, no rescan.
    var similarity: Double = 0.35 {
        didSet { if oldValue != similarity { regroup() } }
    }
    /// Per-photo overrides of the default selection (default: everything except the suggested best).
    private(set) var overrides: [String: Bool] = [:]

    @ObservationIgnored private var items: [AssetInfo] = []
    @ObservationIgnored private var pairs: [SimilarPair] = []
    @ObservationIgnored private var scannedGeneration = -1

    static func threshold(for similarity: Double) -> Float {
        // Exact ≈ 0.05, Loose ≈ 0.75 on Vision revision-2 feature print distance.
        Float(0.05 + similarity * 0.70)
    }

    var thresholdLabel: String {
        switch similarity {
        case ..<0.15: return "Exact"
        case ..<0.4: return "Very close"
        case ..<0.7: return "Similar"
        default: return "Loose"
        }
    }

    var markedCount: Int { groups.reduce(0) { $0 + markedIDs(in: $1).count } }
    var allMarkedIDs: [String] { groups.flatMap { markedIDs(in: $0) } }

    func isMarked(_ id: String, in group: DuplicateGroup) -> Bool {
        overrides[id] ?? (id != group.bestID)
    }

    func toggle(_ id: String, in group: DuplicateGroup) {
        overrides[id] = !isMarked(id, in: group)
    }

    func markedIDs(in group: DuplicateGroup) -> [String] {
        group.assetIDs.filter { isMarked($0, in: group) }
    }

    func scanIfNeeded(library: PhotoLibrary) async {
        guard scannedGeneration != library.generation else { return }
        if case .scanning = phase { return }
        await scan(library: library)
    }

    func scan(library: PhotoLibrary) async {
        let snapshot = library.imagesOldestFirst
        let generation = library.generation
        items = snapshot
        phase = .scanning(done: 0, total: snapshot.count)
        let stream = AsyncStream<ScanEvent> { continuation in
            Task.detached(priority: .userInitiated) {
                let result = DuplicateScanner.run(items: snapshot) { done, total in
                    continuation.yield(.progress(done, total))
                }
                continuation.yield(.finished(result))
                continuation.finish()
            }
        }
        for await event in stream {
            switch event {
            case .progress(let done, let total):
                phase = .scanning(done: done, total: total)
            case .finished(let result):
                pairs = result
            }
        }
        scannedGeneration = generation
        overrides = [:]
        regroup()
        phase = .ready
    }

    func regroup() {
        let limit = Self.threshold(for: similarity)
        var parent = Array(0..<items.count)
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
            return x
        }
        for pair in pairs where pair.distance <= limit {
            let ra = find(pair.a), rb = find(pair.b)
            if ra != rb { parent[rb] = ra }
        }
        var members: [Int: [Int]] = [:]
        for i in 0..<items.count { members[find(i), default: []].append(i) }
        groups = members.values
            .filter { $0.count > 1 }
            .map { indices in
                let infos = indices.map { items[$0] }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                let best = infos.max { Self.score($0) < Self.score($1) } ?? infos[0]
                return DuplicateGroup(id: infos[0].id, assetIDs: infos.map(\.id), bestID: best.id, date: infos[0].date)
            }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Keep-best heuristic: favorites first, then resolution, then the most recent shot (later bursts tend to be steadier).
    static func score(_ info: AssetInfo) -> Double {
        var s = Double(info.pixelWidth * info.pixelHeight) / 1_000_000
        if info.isFavorite { s += 1000 }
        if info.isScreenshot { s -= 5 }
        s += (info.date?.timeIntervalSince1970 ?? 0) / 1e12
        return s
    }

    private enum ScanEvent: Sendable {
        case progress(Int, Int)
        case finished([SimilarPair])
    }
}
