import SwiftUI

struct HomeView: View {
    @Environment(PhotoLibrary.self) private var library
    @Environment(CleanupStore.self) private var cleanup
    @Environment(StoreManager.self) private var store
    @AppStorage(CleanupStore.Keys.totalFreedBytes) private var totalFreedBytes = 0
    @AppStorage(CleanupStore.Keys.totalDeletedCount) private var totalDeletedCount = 0
    @State private var path: [Route] = []
    @State private var didRunDebugLaunch = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    freedCard
                    if library.isLimited { limitedBanner }
                    if !cleanup.pending.isEmpty { trayCard }
                    sessionCards
                    monthsSection
                }
                .padding(.horizontal, KWLayout.screenPadding)
                .padding(.bottom, 32)
            }
            .background(Color.kwBackground.ignoresSafeArea())
            .navigationTitle("Keepwell")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { path.append(.settings) } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                if !store.isPro {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Go Pro") { cleanup.showPaywall = true }
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .session(let session): SwipeSessionView(session: session)
                case .duplicates: DuplicatesView()
                case .tray: ReviewTrayView()
                case .settings: SettingsView()
                }
            }
            .overlay {
                if library.isLoading && !library.hasLoaded { ProgressView() }
            }
        }
        .task(id: library.generation) {
            if !library.hasLoaded { await library.reload() }
            if library.hasLoaded {
                cleanup.prune(validIDs: Set(library.byID.keys))
                await runDebugLaunchIfNeeded()
            }
        }
    }

    private var freedCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SPACE FREED")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.kwTextSecondary)
            Text(formatBytes(Int64(totalFreedBytes)))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color.kwBrandTeal)
                .contentTransition(.numericText())
            Text(totalDeletedCount == 0
                 ? "Your running total appears here after your first cleanup."
                 : "\(totalDeletedCount) photos and videos cleared with Keepwell")
                .font(.subheadline)
                .foregroundStyle(Color.kwTextSecondary)
            if !store.isPro {
                Text("\(cleanup.freeDeletesLeftToday) of \(CleanupStore.freeDailyDeleteLimit) free deletes left today")
                    .font(.caption)
                    .foregroundStyle(Color.kwTextSecondary)
                    .padding(.top, 4)
            }
        }
        .kwCard()
        .padding(.top, 8)
    }

    private var limitedBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            IconChip(systemName: "photo.badge.plus")
            VStack(alignment: .leading, spacing: 4) {
                Text("Limited access").font(.body.weight(.semibold))
                Text("Keepwell can only see the \(library.totalCount) items you selected.")
                    .font(.footnote).foregroundStyle(Color.kwTextSecondary)
                Button("Manage selection") { library.presentLimitedPicker() }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.kwBrandTealText)
            }
        }
        .kwCard()
    }

    private var trayCard: some View {
        Button { path.append(.tray) } label: {
            HStack(spacing: 12) {
                IconChip(systemName: "trash")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review tray").font(.body.weight(.semibold)).foregroundStyle(Color.kwTextPrimary)
                    Text("\(cleanup.pending.count) marked for deletion")
                        .font(.footnote).foregroundStyle(Color.kwTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Color.kwTextSecondary)
            }
            .kwCard()
        }
    }

    private var sessionCards: some View {
        VStack(spacing: 12) {
            Button { path.append(.session(.onThisDay)) } label: {
                sessionRow(icon: "calendar", title: "On this day",
                           detail: library.onThisDay.isEmpty
                           ? "No photos from this date in past years"
                           : "\(library.onThisDay.count) from \(Date.now.formatted(.dateTime.month(.wide).day())) in past years",
                           coverID: library.onThisDay.first)
            }
            .disabled(library.onThisDay.isEmpty)

            Button { path.append(.session(.screenshots)) } label: {
                sessionRow(icon: "camera.viewfinder", title: "Screenshots",
                           detail: library.screenshots.isEmpty
                           ? "No screenshots found"
                           : "\(library.screenshots.count) screenshots to swipe through",
                           coverID: library.screenshots.last)
            }
            .disabled(library.screenshots.isEmpty)

            Button { path.append(.duplicates) } label: {
                sessionRow(icon: "square.on.square", title: "Duplicates & similar",
                           detail: "Grouped on-device, best shot suggested", coverID: nil)
            }
        }
    }

    private func sessionRow(icon: String, title: String, detail: String, coverID: String?) -> some View {
        HStack(spacing: 12) {
            IconChip(systemName: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Color.kwTextPrimary)
                Text(detail).font(.footnote).foregroundStyle(Color.kwTextSecondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            if let coverID { Thumbnail(id: coverID, side: 44).frame(width: 44) }
            Image(systemName: "chevron.right").foregroundStyle(Color.kwTextSecondary)
        }
        .kwCard()
    }

    private var monthsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BY MONTH")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.kwTextSecondary)
                .padding(.top, 8)
            if library.hasLoaded && library.months.isEmpty {
                Text(library.isLimited
                     ? "No photos selected yet. Tap Manage selection to choose some."
                     : "Your library is empty.")
                    .font(.subheadline).foregroundStyle(Color.kwTextSecondary)
                    .kwCard()
            }
            VStack(spacing: 0) {
                ForEach(library.months) { month in
                    Button { path.append(.session(.month(month.id))) } label: {
                        MonthRow(month: month)
                    }
                    if month.id != library.months.last?.id {
                        Divider().overlay(Color.kwSeparator).padding(.leading, 72)
                    }
                }
            }
            .background(Color.kwSurface, in: RoundedRectangle(cornerRadius: KWRadius.grouped, style: .continuous))
        }
    }

    // MARK: Debug launch hooks for Simulator screenshots:
    // -KWScreen home|swipe|month|onthisday|screenshots|duplicates|tray|explainer|freed|paywall|settings
    private func runDebugLaunchIfNeeded() async {
        #if DEBUG
        guard !didRunDebugLaunch, let screen = UserDefaults.standard.string(forKey: "KWScreen") else { return }
        didRunDebugLaunch = true
        switch screen {
        case "home": break
        case "paywall": cleanup.showPaywall = true
        case "month", "swipe": if let m = library.months.first { path = [.session(.month(m.id))] }
        case "onthisday": path = [.session(.onThisDay)]
        case "screenshots": path = [.session(.screenshots)]
        case "duplicates": path = [.duplicates]
        case "settings": path = [.settings]
        case "tray":
            for id in (library.months.first?.assetIDs ?? []).prefix(6) { cleanup.markForDeletion(id) }
            path = [.tray]
        case "explainer":
            cleanup.showExplainer = true
        case "freed":
            await cleanup.debugShowSummary(for: Array((library.months.first?.assetIDs ?? []).prefix(9)))
        default: break
        }
        KWDebugState.set([
            "screen": screen,
            "status": "\(library.status.rawValue)",
            "assets": library.totalCount,
            "months": library.months.count,
            "newestMonthCount": library.months.first?.assetIDs.count ?? 0,
            "onThisDay": library.onThisDay.count,
            "screenshots": library.screenshots.count,
            "pending": cleanup.pending.count,
            "showPaywall": cleanup.showPaywall,
            "showExplainer": cleanup.showExplainer,
            "summaryCount": cleanup.summary?.count ?? 0,
            "summaryBytes": Int(cleanup.summary?.bytes ?? 0),
            "path": path.map { "\($0)" }.joined(separator: ">"),
            "ready": true,
        ])
        #endif
    }
}

private struct MonthRow: View {
    let month: MonthBucket
    @Environment(CleanupStore.self) private var cleanup

    var body: some View {
        let reviewed = month.assetIDs.filter { cleanup.kept.contains($0) || cleanup.isPending($0) }.count
        HStack(spacing: 12) {
            if let cover = month.assetIDs.last {
                Thumbnail(id: cover, side: 48).frame(width: 48)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(month.title).font(.body.weight(.semibold)).foregroundStyle(Color.kwTextPrimary)
                Text(reviewed == 0 ? "\(month.assetIDs.count) \(month.assetIDs.count == 1 ? "item" : "items")"
                     : "\(reviewed) of \(month.assetIDs.count) reviewed")
                    .font(.footnote).foregroundStyle(Color.kwTextSecondary)
            }
            Spacer()
            if reviewed == month.assetIDs.count {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.kwKeep)
            }
            Image(systemName: "chevron.right").foregroundStyle(Color.kwTextSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
