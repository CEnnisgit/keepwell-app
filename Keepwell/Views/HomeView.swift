import SwiftUI

struct HomeView: View {
    @Environment(PhotoLibrary.self) private var library
    @Environment(CleanupStore.self) private var cleanup
    @Environment(StoreManager.self) private var store
    @AppStorage(CleanupStore.Keys.totalFreedBytes) private var totalFreedBytes = 0
    @AppStorage(CleanupStore.Keys.totalDeletedCount) private var totalDeletedCount = 0
    @State private var path: [Route] = []
    @State private var didRunDebugLaunch = false
    @State private var scrollToMonths = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        freedCard
                        if library.isLimited { limitedBanner }
                        if !cleanup.pending.isEmpty { trayCard }
                        sessionCards
                        monthsSection.id("months")
                    }
                    .padding(.horizontal, KWLayout.screenPadding)
                    .padding(.bottom, 32)
                }
                .onChange(of: scrollToMonths) { _, go in
                    if go { proxy.scrollTo("months", anchor: .top) }
                }
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
                    MonthRow(month: month,
                             open: { path.append(.session(.month(month.id))) },
                             reviewAgain: { cleanup.resetMonth(month) })
                    if month.id != library.months.last?.id {
                        Divider().overlay(Color.kwSeparator).padding(.leading, 72)
                    }
                }
            }
            .background(Color.kwSurface, in: RoundedRectangle(cornerRadius: KWRadius.grouped, style: .continuous))
        }
    }

    // MARK: Debug launch hooks for Simulator screenshots:
    // -KWScreen home|swipe|month|onthisday|screenshots|duplicates|tray|explainer|freed|paywall|settings|months|zoom
    private func runDebugLaunchIfNeeded() async {
        #if DEBUG
        guard !didRunDebugLaunch, let screen = UserDefaults.standard.string(forKey: "KWScreen") else { return }
        didRunDebugLaunch = true
        switch screen {
        case "home": break
        case "paywall": cleanup.showPaywall = true
        case "month", "swipe", "zoom": if let m = library.months.first { path = [.session(.month(m.id))] }
        case "months":
            // Newest month half swiped, the next one fully swiped (Done). Writes real saved progress.
            if let first = library.months.first {
                cleanup.resetMonth(first)
                for id in first.assetIDs.prefix(max(1, first.assetIDs.count / 2)) { cleanup.recordReviewed(id, inMonth: first.id) }
            }
            if library.months.count > 1 {
                let second = library.months[1]
                for id in second.assetIDs { cleanup.recordReviewed(id, inMonth: second.id) }
            }
            try? await Task.sleep(for: .milliseconds(300))
            scrollToMonths = true
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
        let progress = cleanup.monthProgress
        let reviewedCounts: [Int] = library.months.map { progress.reviewedCount(in: $0) }
        let monthsDone: Int = library.months.filter { progress.isDone($0) }.count
        var monthsPartial = 0
        var monthProgress: [String] = []
        for (month, n) in zip(library.months, reviewedCounts) {
            if n > 0 && n < month.assetIDs.count { monthsPartial += 1 }
            monthProgress.append("\(month.id):\(n)/\(month.assetIDs.count)")
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
            "monthsDone": monthsDone,
            "monthsPartial": monthsPartial,
            "monthProgress": monthProgress,
            "ready": true,
        ])
        #endif
    }
}

private struct MonthRow: View {
    let month: MonthBucket
    let open: () -> Void
    let reviewAgain: () -> Void
    @Environment(CleanupStore.self) private var cleanup

    var body: some View {
        let total = month.assetIDs.count
        let reviewed = cleanup.monthProgress.reviewedCount(in: month)
        let done = cleanup.monthProgress.isDone(month)
        let items = "\(total) \(total == 1 ? "item" : "items")"
        let progress = "\(reviewed) of \(total)"
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    if let cover = month.assetIDs.last {
                        Thumbnail(id: cover, side: 48).frame(width: 48)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(month.title).font(.body.weight(.semibold)).foregroundStyle(Color.kwTextPrimary)
                        if done {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.kwKeep)
                                Text("Done").fontWeight(.semibold).foregroundStyle(Color.kwTextPrimary)
                                Text("· \(progress)").foregroundStyle(Color.kwTextSecondary)
                            }
                            .font(.footnote)
                        } else if reviewed > 0 {
                            Text("\(progress) reviewed")
                                .font(.footnote).monospacedDigit().foregroundStyle(Color.kwTextSecondary)
                            ProgressView(value: Double(reviewed), total: Double(max(1, total)))
                                .tint(Color.kwBrandTeal)
                                .frame(maxWidth: 140)
                        } else {
                            Text(items).font(.footnote).foregroundStyle(Color.kwTextSecondary)
                        }
                    }
                    Spacer(minLength: 8)
                    if !done {
                        Image(systemName: "chevron.right").foregroundStyle(Color.kwTextSecondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(done ? "\(month.title), Done, \(progress) reviewed"
                                : reviewed > 0 ? "\(month.title), \(progress) reviewed" : "\(month.title), \(items)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open() }
            .accessibilityActions {
                if done { Button("Review again", action: reviewAgain) }
            }

            if done {
                Button(action: reviewAgain) {
                    Text("Review again")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.kwBrandTealText)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.kwBrandTint, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Review \(month.title) again")
                .accessibilityHint("Clears saved progress for this month")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
