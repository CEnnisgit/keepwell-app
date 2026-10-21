import SwiftUI
import Photos

enum Route: Hashable {
    case session(ReviewSession)
    case duplicates
    case tray
    case settings
}

struct RootView: View {
    @Environment(PhotoLibrary.self) private var library
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch library.status {
            case .authorized, .limited:
                HomeView()
            case .notDetermined:
                AccessRequestView()
            default:
                AccessDeniedView()
            }
        }
        .modifier(DeleteFlowModifier())
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { library.refreshStatus() }
        }
        .task {
            library.refreshStatus()
            #if DEBUG
            KWDebugState.set(["screen": UserDefaults.standard.string(forKey: "KWScreen") ?? "",
                              "status": "\(library.status.rawValue)", "ready": false])
            #endif
        }
        #if DEBUG
        .onChange(of: library.status) { _, status in KWDebugState.set(["status": "\(status.rawValue)"]) }
        #endif
    }
}

struct AccessRequestView: View {
    @Environment(PhotoLibrary.self) private var library

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "photo.stack")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(Color.kwBrandTeal)
                .accessibilityHidden(true)
            Text("Clear your camera roll at your own pace")
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
            Text("Swipe left to mark a photo for deletion, right to keep it. Nothing is deleted until you confirm. Deleted photos stay in Recently Deleted for 30 days.")
                .font(.body)
                .foregroundStyle(Color.kwTextSecondary)
                .multilineTextAlignment(.center)
            Label("Everything stays on your iPhone. No accounts, no uploads.", systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(Color.kwTextSecondary)
            Spacer()
            Button("Allow Photo Access") {
                Task { await library.requestAccess() }
            }
            .buttonStyle(PrimaryButtonStyle())
            Text("You can choose all photos or only some. Keepwell works either way.")
                .font(.caption)
                .foregroundStyle(Color.kwTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(KWLayout.screenPadding)
        .background(Color.kwBackground.ignoresSafeArea())
    }
}

struct AccessDeniedView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(Color.kwTextSecondary)
                .accessibilityHidden(true)
            Text("Keepwell needs photo access")
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
            Text("Photo access is turned off for Keepwell. To review and clear photos, allow access in Settings › Apps › Keepwell › Photos. You can pick Full Access or Limited Access.")
                .foregroundStyle(Color.kwTextSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(KWLayout.screenPadding)
        .background(Color.kwBackground.ignoresSafeArea())
    }
}
