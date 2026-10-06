import SwiftUI

struct ReviewTrayView: View {
    @Environment(CleanupStore.self) private var cleanup
    @Environment(StoreManager.self) private var store
    @State private var estimatedBytes: Int64 = 0

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            if cleanup.pending.isEmpty {
                ContentUnavailableView("Tray is empty", systemImage: "tray",
                                       description: Text("Swipe left on photos you want to delete. They wait here until you confirm."))
            } else {
                ScrollView {
                    Text("Tap a photo to keep it instead.")
                        .font(.footnote).foregroundStyle(Color.kwTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(cleanup.pending, id: \.self) { id in
                            Button { withAnimation { cleanup.unmark(id) } } label: {
                                Thumbnail(id: id, side: 110)
                                    .overlay(alignment: .topTrailing) {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, Color.kwDelete)
                                            .font(.title3).padding(6)
                                    }
                            }
                            .accessibilityLabel("Keep instead")
                        }
                    }
                }
                .padding(.horizontal, KWLayout.screenPadding)
                footer
            }
        }
        .background(Color.kwBackground.ignoresSafeArea())
        .navigationTitle("Review tray")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: cleanup.pending) {
            let ids = cleanup.pending
            estimatedBytes = await Task.detached { AssetBytes.total(for: ids) }.value
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                cleanup.requestDelete(cleanup.pending, isPro: store.isPro)
            } label: {
                if cleanup.isDeleting {
                    ProgressView().tint(Color.kwOnBrand)
                } else {
                    Text("Delete \(cleanup.pending.count) · \(formatBytes(estimatedBytes))")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(cleanup.isDeleting)
            Text(store.isPro
                 ? "Deleted photos stay in Recently Deleted for 30 days."
                 : "Deleted photos stay in Recently Deleted for 30 days. \(cleanup.freeDeletesLeftToday) free deletes left today.")
                .font(.caption2).foregroundStyle(Color.kwTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, KWLayout.screenPadding)
        .padding(.vertical, 12)
        .background(Color.kwBackground)
    }
}
