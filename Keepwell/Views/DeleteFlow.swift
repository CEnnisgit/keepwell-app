import SwiftUI

/// Hosts the shared delete flow: one-time explainer → free-quota check → system confirm → freed summary.
struct DeleteFlowModifier: ViewModifier {
    @Environment(CleanupStore.self) private var cleanup
    @Environment(StoreManager.self) private var store

    func body(content: Content) -> some View {
        @Bindable var cleanup = cleanup
        content
            .sheet(isPresented: $cleanup.showExplainer, onDismiss: {
                if !cleanup.hasSeenExplainer { cleanup.cancelRequest() }
            }) {
                DeleteExplainerView(
                    onContinue: { cleanup.explainerAccepted(isPro: store.isPro) },
                    onCancel: { cleanup.cancelRequest() })
                    .presentationDetents([.large])
            }
            .sheet(item: $cleanup.summary) { summary in
                FreedSummaryView(summary: summary)
            }
            .sheet(isPresented: $cleanup.showPaywall) {
                PaywallView()
            }
            .alert("Daily free limit", isPresented: $cleanup.showQuotaAlert) {
                if cleanup.freeDeletesLeftToday > 0 {
                    Button("Delete \(cleanup.freeDeletesLeftToday) now") { cleanup.deleteWithinAllowance() }
                }
                Button("See Keepwell Pro") {
                    cleanup.cancelRequest()
                    cleanup.showPaywall = true
                }
                Button("Not now", role: .cancel) { cleanup.cancelRequest() }
            } message: {
                Text(cleanup.freeDeletesLeftToday > 0
                     ? "The free plan deletes up to \(CleanupStore.freeDailyDeleteLimit) items a day. You have \(cleanup.freeDeletesLeftToday) left today. Swiping and keeping stay unlimited."
                     : "You've used today's \(CleanupStore.freeDailyDeleteLimit) free deletes. Your tray is saved, so you can finish tomorrow, or go unlimited with Keepwell Pro.")
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { cleanup.errorMessage != nil },
                set: { if !$0 { cleanup.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(cleanup.errorMessage ?? "")
            }
    }
}

struct DeleteExplainerView: View {
    var onContinue: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.kwBrandTeal)
                .padding(.top, 28)
            Text("Deleted photos go to Recently Deleted for 30 days")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Deleted photos stay in Recently Deleted for 30 days. To recover one, open Photos › Albums › Recently Deleted. Keepwell's Undo button only reverses swipes before you confirm a delete.")
                .foregroundStyle(Color.kwTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("iOS will ask you to confirm each batch. Keepwell never deletes anything without that confirmation.")
                .font(.footnote)
                .foregroundStyle(Color.kwTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Got it, continue", action: onContinue)
                .buttonStyle(PrimaryButtonStyle())
            Button("Cancel", action: onCancel)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.kwBrandTealText)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, KWLayout.screenPadding)
        .padding(.bottom, 12)
        .background(Color.kwBackground.ignoresSafeArea())
    }
}

struct FreedSummaryView: View {
    let summary: FreedSummary
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CleanupStore.Keys.totalFreedBytes) private var totalFreedBytes = 0

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 6)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Text("See exactly what you freed")
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                    VStack(spacing: 4) {
                        Text(formatBytes(summary.bytes))
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.kwBrandTeal)
                        Text("\(summary.count) \(summary.count == 1 ? "item" : "items") moved to Recently Deleted")
                            .font(.headline)
                    }
                    .kwCard()
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(Array(summary.thumbnails.enumerated()), id: \.offset) { _, image in
                            Color.clear.aspectRatio(1, contentMode: .fit)
                                .overlay { Image(uiImage: image).resizable().scaledToFill() }
                                .clipShape(RoundedRectangle(cornerRadius: KWRadius.thumb, style: .continuous))
                        }
                    }
                    if summary.count > summary.thumbnails.count {
                        Text("+ \(summary.count - summary.thumbnails.count) more")
                            .font(.footnote).foregroundStyle(Color.kwTextSecondary)
                    }
                    HStack {
                        Text("Total freed with Keepwell").font(.body.weight(.semibold))
                        Spacer()
                        Text(formatBytes(Int64(totalFreedBytes)))
                            .font(.system(.body, design: .rounded).weight(.bold)).monospacedDigit()
                    }
                    .kwCard()
                    Text("Deleted photos stay in Recently Deleted for 30 days. To recover one, open Photos › Albums › Recently Deleted. Storage is released once they leave Recently Deleted.")
                        .font(.caption2)
                        .foregroundStyle(Color.kwTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, KWLayout.screenPadding)
                .padding(.bottom, 24)
            }
            .background(Color.kwBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, KWLayout.screenPadding)
                    .padding(.bottom, 8)
                    .background(Color.kwBackground)
            }
        }
    }
}
