import SwiftUI
import StoreKit

struct SettingsView: View {
    @Environment(StoreManager.self) private var store
    @Environment(CleanupStore.self) private var cleanup
    @Environment(PhotoLibrary.self) private var library
    @Environment(\.openURL) private var openURL
    @State private var showManageSubscriptions = false
    @State private var restoring = false

    var body: some View {
        List {
            Section("Keepwell Pro") {
                HStack {
                    Label("Status", systemImage: "star.circle")
                    Spacer()
                    Text(store.isPro ? "Pro · \(store.activePlanName ?? "Active")" : "Free")
                        .foregroundStyle(store.isPro ? Color.kwBrandTealText : Color.kwTextSecondary)
                        .fontWeight(.semibold)
                }
                if !store.isPro {
                    Text("Free: unlimited swiping and keeping, \(CleanupStore.freeDailyDeleteLimit) deletes a day (\(cleanup.freeDeletesLeftToday) left today).")
                        .font(.footnote).foregroundStyle(Color.kwTextSecondary)
                    Button { cleanup.showPaywall = true } label: {
                        Label("Upgrade to Keepwell Pro", systemImage: "sparkles")
                    }
                }
                Button {
                    restoring = true
                    Task { await store.restore(); restoring = false }
                } label: {
                    HStack {
                        Label("Restore Purchases", systemImage: "arrow.clockwise")
                        if restoring { Spacer(); ProgressView() }
                    }
                }
                Button { showManageSubscriptions = true } label: {
                    Label("Manage Subscription", systemImage: "creditcard")
                }
            }

            Section("Photo access") {
                HStack {
                    Label("Access", systemImage: "photo.on.rectangle")
                    Spacer()
                    Text(library.isLimited ? "Limited (\(library.totalCount) items)" : "Full")
                        .foregroundStyle(Color.kwTextSecondary)
                }
                if library.isLimited {
                    Button("Manage selection") { library.presentLimitedPicker() }
                }
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }

            Section {
                Label("Everything happens on your iPhone. Keepwell has no accounts, no analytics and makes no network requests. Deleted photos stay in Recently Deleted for 30 days.", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(Color.kwTextSecondary)
            } header: { Text("Privacy") }

            Section("About") {
                Button("Privacy Policy") { openURL(KWLinks.privacy) }
                Button("Terms of Use") { openURL(KWLinks.terms) }
                Button("Support") { openURL(KWLinks.support) }
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(Color.kwTextSecondary)
                }
            }
        }
        .tint(Color.kwBrandTealText)
        .scrollContentBackground(.hidden)
        .background(Color.kwBackground.ignoresSafeArea())
        .navigationTitle("Settings")
        .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
    }
}
