import SwiftUI

struct DuplicatesView: View {
    @Environment(PhotoLibrary.self) private var library
    @Environment(CleanupStore.self) private var cleanup
    @Environment(StoreManager.self) private var store
    @Environment(DuplicateEngine.self) private var engine

    var body: some View {
        @Bindable var engine = engine
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sliderCard(similarity: $engine.similarity)
                content
            }
            .padding(.horizontal, KWLayout.screenPadding)
            .padding(.bottom, 24)
        }
        .background(Color.kwBackground.ignoresSafeArea())
        .navigationTitle("Duplicates & similar")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if engine.phase == .ready && engine.markedCount > 0 {
                Button {
                    cleanup.requestDelete(engine.allMarkedIDs, isPro: store.isPro)
                } label: {
                    Text("Delete \(engine.markedCount) extras, keep the best")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(cleanup.isDeleting)
                .padding(.horizontal, KWLayout.screenPadding)
                .padding(.vertical, 8)
                .background(Color.kwBackground)
            }
        }
        .task(id: library.generation) {
            #if DEBUG
            if engine.needsScan(generation: library.generation) { KWDebugState.set(["dupPhase": "scanning"]) }
            #endif
            await engine.scanIfNeeded(library: library)
            #if DEBUG
            let stats = engine.lastStats
            KWDebugState.set(["dupPhase": engine.phase == .ready ? "ready" : "scanning",
                              "dupGroups": engine.groups.count, "dupMarked": engine.markedCount,
                              "dupItems": stats.items, "dupFeaturePrints": stats.featurePrints, "dupHashes": stats.hashes,
                              "dupComparisons": stats.comparisons, "dupPairs": stats.pairs,
                              "dupMinDistance": Double(stats.minDistance),
                              "dupSmallest": stats.smallestDistances.map { String(format: "%.3f", $0) }.joined(separator: " "),
                              "dupSource": stats.source.rawValue,
                              "dupProbeDistance": stats.probeDistance.map { Double($0) } ?? -1])
            #endif
        }
    }

    private func sliderCard(similarity: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("How similar")
                    .font(.title3.weight(.bold))
                Spacer()
                Text(engine.thresholdLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.kwBrandTealText)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.kwBrandTint, in: RoundedRectangle(cornerRadius: KWRadius.badge, style: .continuous))
            }
            Slider(value: similarity, in: 0...1) {
                Text("How similar")
            } minimumValueLabel: {
                Text("Exact").font(.footnote.weight(.semibold))
            } maximumValueLabel: {
                Text("Loose").font(.footnote.weight(.semibold))
            }
            .accessibilityValue(engine.thresholdLabel)
            Text(engine.phase == .ready
                 ? "\(engine.groups.count) groups · \(engine.markedCount) extras selected. Slide to regroup instantly."
                 : "Slide toward Exact for true duplicates, toward Loose for similar shots.")
                .font(.footnote)
                .foregroundStyle(Color.kwTextSecondary)
        }
        .kwCard()
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch engine.phase {
        case .idle:
            ProgressView().frame(maxWidth: .infinity)
        case .scanning(let done, let total):
            VStack(spacing: 8) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                Text("Comparing photos on your iPhone… \(done) of \(total)")
                    .font(.footnote).foregroundStyle(Color.kwTextSecondary)
            }
            .kwCard()
        case .ready:
            if engine.groups.isEmpty {
                ContentUnavailableView("No similar photos at this setting", systemImage: "square.on.square",
                                       description: Text("Try sliding toward Loose."))
            } else {
                ForEach(engine.groups) { group in
                    GroupCard(group: group)
                }
            }
        }
    }
}

private struct GroupCard: View {
    let group: DuplicateGroup
    @Environment(DuplicateEngine.self) private var engine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(group.assetIDs.count) photos")
                    .font(.body.weight(.semibold))
                if let date = group.date {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote).foregroundStyle(Color.kwTextSecondary)
                }
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(group.assetIDs, id: \.self) { id in
                        let marked = engine.isMarked(id, in: group)
                        Button { engine.toggle(id, in: group) } label: {
                            AssetImage(id: id, targetSize: CGSize(width: 104, height: 104))
                                .frame(width: 104, height: 104)
                                .clipShape(RoundedRectangle(cornerRadius: KWRadius.thumb, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: KWRadius.thumb, style: .continuous)
                                        .stroke(marked ? Color.kwDelete : Color.kwKeep, lineWidth: 3)
                                }
                                .overlay(alignment: .bottomLeading) {
                                    if id == group.bestID {
                                        Text("BEST")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(Color.kwOnBrand)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.kwBrandTeal, in: RoundedRectangle(cornerRadius: KWRadius.badge, style: .continuous))
                                            .padding(6)
                                    }
                                }
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: marked ? "trash.circle.fill" : "checkmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, marked ? Color.kwDelete : Color.kwKeep)
                                        .font(.title3).padding(4)
                                }
                        }
                        .accessibilityLabel(marked ? "Marked for deletion" : (id == group.bestID ? "Best shot, kept" : "Kept"))
                    }
                }
            }
            Text("Suggested keep: your favorite, else the highest-resolution, most recent shot. Tap any photo to switch.")
                .font(.caption).foregroundStyle(Color.kwTextSecondary)
        }
        .kwCard()
    }
}
