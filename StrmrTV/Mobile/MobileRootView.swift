#if os(iOS)
import SwiftUI

/// The iPhone / iPad app's root: the same session phases as the TV's `RootView`, with phone
/// screens for the profile picker, PIN entry and the signed-in app. Server and sign-in
/// screens are shared with tvOS.
struct MobileRootView: View {
    @StateObject private var session = AppSession.shared
    @StateObject private var playback = PlaybackCoordinator.shared
    @StateObject private var connection = MobileConnection.shared
    @ObservedObject private var monitor = MobileNetworkMonitor.shared
    /// Offline at launch, Downloads opens by itself once (as the Expo app redirects there).
    @State private var openedDownloadsOffline = false
    #if DEBUG
    @State private var showsConnectionSettings = DebugPrefill.showConnectionSettings
    #endif

    var body: some View {
        Group {
            switch session.phase {
            case .starting:
                MobileStartingView()
            case .server:
                ServerConnectView()
            case .login:
                LoginView()
            case .profiles:
                MobileProfilePicker()
            case .ready:
                // Rebuilt per profile so every screen reloads its data.
                MobileMainView().id(session.profile?.id)
            case let .unavailable(message):
                MobileOfflineView(message: message)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if session.phase == .ready { MobileConnectionBanner() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.brandBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onChange(of: session.phase) { _, phase in
            connection.phaseChanged(phase)
            if case .unavailable = phase, monitor.isDeviceOffline, !openedDownloadsOffline {
                openedDownloadsOffline = true
                connection.showsOfflineDownloads = true
            }
        }
        .fullScreenCover(isPresented: $connection.showsOfflineDownloads) {
            MobileOfflineDownloads()
        }
        #if DEBUG
        .sheet(isPresented: $showsConnectionSettings) {
            NavigationStack { MobileConnectionSettingsView() }
        }
        #endif
        .task {
            connection.start()
            AdaptiveThroughput.shared.start()
            await session.start()
            #if DEBUG
            if ChromeProbe.isEnabled { ChromeProbe.present() }
            if let url = SoftwarePlayerProbe.url { SoftwarePlayerProbe.present(url) }
            #endif
        }
        .disabled(playback.resolving != nil)
        .overlay {
            if let request = playback.resolving {
                MobilePlaybackLoadingView(request: request, stage: playback.resolvingStage,
                                          detail: playback.resolvingDetail) {
                    playback.cancelResolve()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: playback.resolving == nil)
        .modifier(MobileProfileLockPrompt(session: session))
        .alert(
            "Playback Error",
            isPresented: Binding(get: { playback.errorMessage != nil }, set: { if !$0 { playback.errorMessage = nil } }),
            presenting: playback.errorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }
}

/// Asks for a PIN when a request hits a locked profile mid-session (`AppSession.pinChallenge`).
struct MobileProfileLockPrompt: ViewModifier {
    @ObservedObject var session: AppSession

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: Binding(get: { session.pinChallenge }, set: { _ in })) { challenge in
                MobilePINEntryView(
                    profile: challenge.profile,
                    notice: String(localized: "This profile is locked. Enter its PIN to continue."),
                    verify: { await session.verifyChallenge(pin: $0) },
                    onCancel: { session.cancelChallenge() }
                )
            }
    }
}
#endif
