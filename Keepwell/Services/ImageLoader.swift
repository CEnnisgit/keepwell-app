import Photos
import UIKit

enum ImageLoader {
    /// Loads one image for an asset. With `.highQualityFormat` Photos calls the handler exactly once.
    static func image(for id: String, size: CGSize, contentMode: PHImageContentMode = .aspectFill) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true // iCloud Photos originals are fetched by the system Photos service
        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: contentMode, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Zoom-quality image: opportunistic delivery (a quick degraded frame, then the full one) from what is
    /// already on the device. Network access is off, so an iCloud-only original simply never upgrades.
    /// The request is cancelled when the consumer stops iterating.
    static func detailImages(for id: String, size: CGSize) -> AsyncStream<UIImage> {
        AsyncStream { continuation in
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
                continuation.finish()
                return
            }
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = false
            let requestID = PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit,
                                                                  options: options) { image, info in
                if let image { continuation.yield(image) }
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !degraded || image == nil { continuation.finish() }
            }
            continuation.onTermination = { _ in PHImageManager.default().cancelImageRequest(requestID) }
        }
    }
}

enum AssetBytes {
    /// Sum of PHAssetResource file sizes (original plus any edited renditions).
    static func total(for ids: [String]) -> Int64 {
        perAsset(for: ids).values.reduce(0, +)
    }

    static func perAsset(for ids: [String]) -> [String: Int64] {
        guard !ids.isEmpty else { return [:] }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var out: [String: Int64] = [:]
        for i in 0..<assets.count {
            let asset = assets.object(at: i)
            var bytes: Int64 = 0
            for resource in PHAssetResource.assetResources(for: asset) {
                if let n = resource.value(forKey: "fileSize") as? NSNumber { bytes += n.int64Value }
            }
            out[asset.localIdentifier] = bytes
        }
        return out
    }
}
