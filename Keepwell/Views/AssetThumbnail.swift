import SwiftUI
import Photos

/// Square-cropped (or fitted) thumbnail for a PhotoKit asset.
struct AssetImage: View {
    let id: String
    var targetSize: CGSize
    var contentMode: ContentMode = .fill
    @State private var image: UIImage?
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
            let px = CGSize(width: targetSize.width * displayScale, height: targetSize.height * displayScale)
            image = await ImageLoader.image(for: id, size: px,
                                            contentMode: contentMode == .fill ? .aspectFill : .aspectFit)
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
