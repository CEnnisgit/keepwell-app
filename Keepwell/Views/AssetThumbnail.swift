import SwiftUI
import Photos

/// Square-cropped (or fitted) thumbnail for a PhotoKit asset.
struct AssetImage: View {
    let id: String
    var targetSize: CGSize
    var contentMode: ContentMode = .fill
    /// Zoomed in: replace the fitted image with one sized for `detailScale` (opportunistic, on-device only).
    var wantsDetail = false
    var detailScale: CGFloat = CardGestureState.maxScale
    @State private var image: UIImage?
    @State private var hasDetail = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            Color.kwSeparator
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            }
        }
        .task(id: id) {
            hasDetail = false
            let px = CGSize(width: targetSize.width * displayScale, height: targetSize.height * displayScale)
            let base = await ImageLoader.image(for: id, size: px,
                                               contentMode: contentMode == .fill ? .aspectFill : .aspectFit)
            if !hasDetail { image = base }
        }
        .task(id: wantsDetail ? id : nil) {
            guard wantsDetail, !hasDetail else { return }
            // Sized for the deepest zoom, capped at about 12 MP so a large original never blows up memory.
            let base = CGSize(width: targetSize.width * displayScale, height: targetSize.height * displayScale)
            let factor = min(detailScale, (12_000_000 / max(1, base.width * base.height)).squareRoot())
            let px = CGSize(width: base.width * factor, height: base.height * factor)
            for await frame in ImageLoader.detailImages(for: id, size: px) {
                // The opportunistic first frame can be smaller than what is already shown.
                if frame.size.width * frame.scale > (image.map { $0.size.width * $0.scale } ?? 0) {
                    image = frame
                    hasDetail = true
                    #if DEBUG
                    KWDebugState.set(["detailPixelWidth": Int(frame.size.width * frame.scale)])
                    #endif
                }
            }
        }
    }
}

struct Thumbnail: View {
    let id: String
    var side: CGFloat = 80
    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { AssetImage(id: id, targetSize: CGSize(width: side, height: side)) }
            .clipShape(RoundedRectangle(cornerRadius: KWRadius.thumb, style: .continuous))
    }
}
