import AVKit
import SwiftUI

/// The backdrop trailer's picture, laid over the backdrop image; transparent until frames flow.
struct TrailerBackdropVideo: View {
    @ObservedObject var trailer: TrailerController

    var body: some View {
        PlayerLayerView(player: trailer.player)
            .opacity(trailer.showing ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private struct PlayerLayerView: UIViewRepresentable {
        let player: AVPlayer

        func makeUIView(context: Context) -> LayerView {
            let view = LayerView()
            view.playerLayer.player = player
            view.playerLayer.videoGravity = .resizeAspect
            view.backgroundColor = .black
            return view
        }

        func updateUIView(_ view: LayerView, context: Context) {}

        final class LayerView: UIView {
            override static var layerClass: AnyClass { AVPlayerLayer.self }
            var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        }
    }
}

/// The details page's shade over its backdrop (and the backdrop trailer): bottom-weighted, so
/// the art stays clear at the top and the text sits on dark below, plus a fade from the left
/// edge. Hidden while the trailer plays immersive, so it isn't left darkening the video.
struct DetailsBackdropShade: View {
    let hidden: Bool

    var body: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(0.35), location: 0.45),
                .init(color: .black.opacity(0.9), location: 0.8),
                .init(color: .black, location: 1),
            ], startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [.black.opacity(0.8), .black.opacity(0.2), .clear],
                           startPoint: .leading, endPoint: .trailing)
        }
        .opacity(hidden ? 0 : 1)
        .allowsHitTesting(false)
    }
}

/// A trailer full screen in the stock player (transport bar, Menu closes); closes at the end.
/// It never switches the TV's display mode: a short SDR trailer isn't worth an HDMI resync.
struct TrailerPlayerView: UIViewControllerRepresentable {
    let url: URL
    let onFinish: @MainActor @Sendable () -> Void

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.appliesPreferredDisplayCriteriaAutomatically = false
        let player = AVPlayer(url: url)
        controller.player = player
        context.coordinator.observe(player.currentItem, onFinish: onFinish)
        player.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        controller.player?.pause()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var endObserver: NSObjectProtocol?

        func observe(_ item: AVPlayerItem?, onFinish: @escaping @MainActor @Sendable () -> Void) {
            endObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
            ) { _ in MainActor.assumeIsolated { onFinish() } }
        }

        deinit { if let endObserver { NotificationCenter.default.removeObserver(endObserver) } }
    }
}

/// Wires the trailer into the details page: immersive focus, the stop conditions and the
/// full-screen player.
struct DetailsTrailerModifier: ViewModifier {
    @ObservedObject var trailer: TrailerController
    var focus: FocusState<DetailsView.DetailsFocus?>.Binding
    /// A play is resolving or the player is up.
    let playbackStarting: Bool
    /// A menu over the page is up (source picker, Add to List…, watch state, More Options).
    let menuOpen: Bool
    /// Where focus returns when the header comes back.
    @State private var focusBeforeImmersive: DetailsView.DetailsFocus?

    func body(content: Content) -> some View {
        content
            .overlay {
                // Holds focus while the header is faded, so a press only brings it back
                // instead of acting on an invisible button.
                if trailer.immersive {
                    // A bare focusable view, not a Button: a full-screen button draws the system
                    // focus platter over the whole trailer.
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .focusable()
                        .focusEffectDisabled()
                        .focused(focus, equals: .immersive)
                        .onTapGesture { trailer.wake() }
                        .onMoveCommand { _ in trailer.wake() }
                        .onExitCommand { trailer.wake() }
                        .accessibilityLabel(Text("Show details"))
                        .accessibilityAddTraits(.isButton)
                        .ignoresSafeArea()
                }
            }
            .onPlayPauseCommand { if trailer.showing { trailer.togglePause() } }
            .onChange(of: trailer.immersive) { _, immersive in
                if immersive {
                    focusBeforeImmersive = focus.wrappedValue
                    focus.wrappedValue = .immersive
                } else if focus.wrappedValue == .immersive {
                    focus.wrappedValue = focusBeforeImmersive ?? .action(.primary)
                }
            }
            .onChange(of: focus.wrappedValue) { old, new in
                guard let new, new != .immersive else { return }
                switch new.row {
                // Moving within the header keeps the trailer and restarts the fade timer.
                case .overview, .actions: if old == .immersive || trailer.showing { trailer.wake() }
                // Down to the episodes or related rows: the Expo page stops it there.
                default: trailer.dismiss("focus left the header")
                }
            }
            .onChange(of: playbackStarting) { _, starting in if starting { trailer.dismiss("playback") } }
            // Opening any of the page's menus stops it for the rest of the visit, as the Expo
            // page's `dismissTrailerAutoPlay` on those controls (a dismissed trailer never
            // restarts, so closing the menu leaves the backdrop image).
            .onChange(of: menuOpen) { _, open in if open { trailer.dismiss("menu open") } }
            .onDisappear { trailer.dismiss("page gone") }
            .fullScreenCover(item: $trailer.fullScreen) { item in
                TrailerPlayerView(url: item.url) { trailer.fullScreen = nil }
                    .ignoresSafeArea()
            }
    }
}
