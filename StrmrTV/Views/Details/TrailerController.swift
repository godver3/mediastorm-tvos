import AVFoundation
import SwiftUI

/// The details page's trailer, as the Expo TV page runs it. The server's pick is downloaded as
/// soon as it is known. With `autoPlayTrailersTV` on it plays behind the header two seconds
/// after the page loads, at 40% volume, and four seconds in the header fades out (immersive)
/// until a press brings it back. It stops for good on this page once focus leaves the header,
/// playback starts, or the user opens the trailer full screen. The Trailer button pauses /
/// resumes the backdrop trailer, else plays it full screen.
@MainActor
final class TrailerController: ObservableObject {
    /// A trailer to play full screen.
    struct FullScreen: Identifiable {
        let id = UUID()
        let url: URL
    }

    /// The page has a trailer; the Trailer button shows.
    @Published private(set) var available = false
    /// The backdrop trailer is showing frames (the backdrop image fades out under it).
    @Published private(set) var showing = false
    @Published private(set) var paused = false
    /// The header is faded out over the backdrop trailer.
    @Published private(set) var immersive = false
    /// Getting a URL for a full-screen play.
    @Published private(set) var preparingFullScreen = false
    @Published var fullScreen: FullScreen?
    /// The full-screen trailer couldn't be fetched; shown under the header.
    @Published private(set) var errorMessage: String?

    let player = AVPlayer()
    private var trailer: Trailer?
    private var readyURL: URL?
    private var autoplay = false
    /// Stopped for good on this page (as the Expo page's `dismissTrailerAutoPlay`).
    private var dismissed = false
    private var prepareTask: Task<Void, Never>?
    private var immersiveTask: Task<Void, Never>?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private let loadedAt = Date()

    private static let log = AppLog(category: "trailer")
    private static let startDelay: TimeInterval = 2
    private static let immersiveDelay: Duration = .seconds(4)
    private static let volume: Float = 0.4

    /// The page's trailer from details; a reload with the same one keeps what is under way.
    func prepare(_ next: Trailer?) {
        guard next != trailer else { return }
        trailer = next
        available = next != nil
        readyURL = nil
        prepareTask?.cancel()
        guard let next else { return }
        prepareTask = Task { [weak self] in
            async let settings = APIClient.shared.playbackSettings()
            let url = await APIClient.shared.trailerURL(for: next)
            var autoplay = await TrailerSettingsStore.shared.autoPlay(server: settings.autoPlayTrailers)
            #if DEBUG
            autoplay = autoplay || DebugPrefill.autoPlayTrailers
            #endif
            guard let self, !Task.isCancelled else { return }
            self.readyURL = url
            self.autoplay = autoplay
            guard autoplay, url != nil else { return }
            let wait = Self.startDelay - Date().timeIntervalSince(self.loadedAt)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            self.startBackdrop()
        }
    }

    // MARK: Backdrop

    private func startBackdrop() {
        guard !dismissed, let readyURL, player.currentItem == nil,
              PlaybackCoordinator.shared.resolving == nil, !PlaybackCoordinator.shared.isPresentingPlayer
        else { return }
        let item = AVPlayerItem(url: readyURL)
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            // A trailer that won't play just leaves the backdrop image, as in the Expo app.
            guard item.status == .failed else { return }
            Task { @MainActor in self?.dismiss("failed") }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.dismiss("ended") } }
        Self.log.info("backdrop trailer started")
        player.volume = Self.volume
        player.replaceCurrentItem(with: item)
        player.play()
        paused = false
        Task { [weak self] in
            // Shown once frames flow, so a slow start keeps the backdrop image up.
            while let self, self.player.currentItem === item, !self.showing {
                if self.player.timeControlStatus == .playing {
                    withAnimation(.easeInOut(duration: 0.4)) { self.showing = true }
                    self.scheduleImmersive()
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Any press over the trailer: the header comes back, then fades again if it keeps playing.
    func wake() {
        if immersive { withAnimation(.easeInOut(duration: 0.4)) { immersive = false } }
        scheduleImmersive()
    }

    private func scheduleImmersive() {
        immersiveTask?.cancel()
        guard showing, !paused else { return }
        immersiveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.immersiveDelay)
            guard let self, !Task.isCancelled, self.showing, !self.paused else { return }
            withAnimation(.easeInOut(duration: 0.4)) { self.immersive = true }
        }
    }

    func togglePause() {
        guard player.currentItem != nil else { return }
        paused.toggle()
        if paused { player.pause() } else { player.play() }
        wake()
    }

    /// Stops the backdrop trailer for the rest of this page.
    func dismiss(_ reason: String) {
        if !dismissed {
            Self.log.info("backdrop trailer dismissed (\(reason), was \(player.currentItem == nil ? "not started" : "playing"))")
        }
        dismissed = true
        immersiveTask?.cancel()
        statusObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        withAnimation(.easeInOut(duration: 0.4)) {
            showing = false
            immersive = false
        }
    }

    // MARK: Trailer button

    func buttonPressed() {
        if player.currentItem != nil {
            togglePause()
            return
        }
        guard let trailer, !preparingFullScreen else { return }
        dismiss("full screen")
        preparingFullScreen = true
        errorMessage = nil
        Task {
            // Fetched again: the server deletes an unplayed download about a minute after it is
            // ready, and returns the same file while it is still there.
            let url = await APIClient.shared.trailerURL(for: trailer)
            preparingFullScreen = false
            if let url { fullScreen = FullScreen(url: url) } else { errorMessage = String(localized: "Unable to play trailer") }
        }
    }
}
