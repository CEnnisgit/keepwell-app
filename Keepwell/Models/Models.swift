import Foundation
import Photos
import UIKit

/// Sendable snapshot of the bits of a PHAsset we need. PHAsset itself never crosses actors.
struct AssetInfo: Sendable, Hashable, Identifiable {
    let id: String
    let date: Date?
    let isVideo: Bool
    let duration: TimeInterval
    let pixelWidth: Int
    let pixelHeight: Int
    let isFavorite: Bool
    let isScreenshot: Bool

    init(_ asset: PHAsset) {
        id = asset.localIdentifier
        date = asset.creationDate
        isVideo = asset.mediaType == .video
        duration = asset.duration
        pixelWidth = asset.pixelWidth
        pixelHeight = asset.pixelHeight
        isFavorite = asset.isFavorite
        isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
    }
}

struct MonthBucket: Sendable, Hashable, Identifiable {
    let id: String          // "2026-09"
    let title: String       // "September 2026"
    let assetIDs: [String]  // oldest first
}

enum ReviewSession: Hashable {
    case month(String)
    case onThisDay
    case screenshots
}

struct FreedSummary: Identifiable {
    let id = UUID()
    let count: Int
    let bytes: Int64
    let thumbnails: [UIImage]
    let date: Date
}

struct DuplicateGroup: Identifiable, Sendable {
    let id: String
    let assetIDs: [String]  // newest first
    let bestID: String
    let date: Date?
}
