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
