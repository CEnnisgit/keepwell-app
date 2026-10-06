import SwiftUI

@main
struct KeepwellApp: App {
    @State private var library = PhotoLibrary()
    @State private var cleanup = CleanupStore()
    @State private var store = StoreManager()
    @State private var duplicates = DuplicateEngine()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(cleanup)
                .environment(store)
                .environment(duplicates)
                .tint(Color.kwBrandTeal)
                .task { await store.start() }
        }
    }
}
