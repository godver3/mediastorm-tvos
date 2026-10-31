import SwiftUI

@main
struct StrmrTVApp: App {
    init() {
        CrashReporter.install()
        MainThreadWatchdog.shared.start()
        EngineLogBridge.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // Top Shelf links; held by the router until the main tabs are up.
                .onOpenURL { DeepLinkRouter.shared.open($0) }
        }
    }
}

struct RootView: View {
    @StateObject private var session = AppSession.shared
    @StateObject private var playback = PlaybackCoordinator.shared

    var body: some View {
        Group {
            switch session.phase {
            case .starting:
                ProgressView("Connecting…")
            case .server:
                ServerConnectView()
            case .login:
                LoginView()
            case .profiles:
                ProfilePickerView()
            case .ready:
                // Rebuilt per profile so every tab reloads its data.
                MainTabs().id(session.profile?.id)
            case let .unavailable(message):
                StartupUnavailableView(message: message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if session.phase != .ready { Color.brandBackground.ignoresSafeArea() }
        }
        .task {
            #if DEBUG
            if ChromeProbe.isEnabled { ChromeProbe.present(); return }
            if let url = SoftwarePlayerProbe.url { SoftwarePlayerProbe.present(url); return }
            #endif
            AdaptiveThroughput.shared.start()
            await session.start()
        }
        // The page underneath can't take focus or presses while the loading art is up.
        .disabled(playback.resolving != nil)
        .overlay {
            if let request = playback.resolving {
                PlaybackLoadingView(request: request, stage: playback.resolvingStage,
                                    detail: playback.resolvingDetail) {
                    playback.cancelResolve()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: playback.resolving == nil)
        .modifier(ProfileLockPrompt(session: session))
        .guardsUnfocusedMenu()
        .alert(
            "Playback Error",
            isPresented: Binding(get: { playback.errorMessage != nil }, set: { if !$0 { playback.errorMessage = nil } }),
            presenting: playback.errorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }
}

/// A stored session couldn't be checked because the server didn't answer.
struct StartupUnavailableView: View {
    @ObservedObject private var session = AppSession.shared
    let message: String

    var body: some View {
        OnboardingLayout(
            title: "Couldn't Connect to \(session.serverURL?.host() ?? String(localized: "the Server"))",
            subtitle: Text(message)
        ) {
            HStack(spacing: 40) {
                Button("Try Again") { Task { await session.retryStartup() } }
                Button("Change Server") { session.changeServer() }
            }
        }
    }
}
