import SwiftUI

/// Full-screen stream-start art, from the Play / Resume / episode / source press until the
/// player is on screen: the episode still (else the title backdrop) under a dark gradient,
/// the logo, the episode line and the resolve stage. Menu cancels the resolve.
///
/// It takes focus while it is up (the page underneath is disabled), so Menu reaches it
/// instead of popping the page, and stray presses can't start anything behind it.
struct PlaybackLoadingView: View {
    let request: PlaybackRequest
    let stage: String
    let detail: String?
    let onCancel: () -> Void

    @FocusState private var focused: Bool
    @State private var drift = false
    @State private var artIndex = 0

    /// Rotation timing from the Expo app's preroll artwork.
    private static let rotationInterval: Duration = .seconds(4)
    private static let crossfade = 1.0

    private var artURLs: [String] {
        let urls = request.artwork.backdropURLs
        return urls.isEmpty ? [request.episode?.imageURL ?? request.title.backdropURL].compactMap { $0 } : urls
    }

    private var backdropURL: URL? {
        let urls = artURLs
        return urls.isEmpty ? nil : Artwork.url(urls[artIndex % urls.count])
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Backdrop(url: backdropURL, fade: Self.crossfade)
                // A slow push-in, so a long resolve doesn't sit on a frozen frame.
                .scaleEffect(drift ? 1.06 : 1, anchor: .center)
                .animation(.linear(duration: 30), value: drift)
                .overlay(
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.15), location: 0),
                        .init(color: .black.opacity(0.45), location: 0.45),
                        .init(color: .black.opacity(0.92), location: 0.85),
                        .init(color: .black, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                )
                .overlay(
                    LinearGradient(colors: [.black.opacity(0.75), .black.opacity(0.15), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                titleArt
                if let episode = request.episode {
                    Text(episodeLine(episode))
                        .font(.system(size: 34, weight: .semibold))
                        .lineLimit(1)
                }
                status.padding(.top, 26)
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 90)
            .frame(maxWidth: 1200, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onExitCommand(perform: onCancel)
        .onAppear {
            focused = true
            drift = true
        }
        .task {
            // Cross-fade through the title's backdrops while the stream starts. An image
            // that fails to load leaves the previous one up until the next turn.
            guard artURLs.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.rotationInterval)
                guard !Task.isCancelled else { return }
                artIndex += 1
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("PlaybackLoading")
    }

    @ViewBuilder private var titleArt: some View {
        if let url = Artwork.logoURL(request.artwork.logoURL) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fit)
                    .shadow(color: .black.opacity(0.5), radius: 20)
            } placeholder: { titleText }
            .frame(maxWidth: 620, maxHeight: 210, alignment: .bottomLeading)
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(request.title.name)
            .font(.system(size: 76, weight: .bold))
            .lineLimit(2)
            .minimumScaleFactor(0.7)
    }

    private func episodeLine(_ episode: PlaybackRequest.EpisodeInfo) -> String {
        guard let name = episode.name, !name.isEmpty else { return episode.code }
        return "\(episode.code) · \(name)"
    }

    private var status: some View {
        HStack(alignment: .firstTextBaseline, spacing: 22) {
            ProgressView()
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 10 }
            VStack(alignment: .leading, spacing: 6) {
                Text(stage)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: stage)
                if let detail {
                    Text(detail)
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .frame(height: 80, alignment: .topLeading)  // fixed, so a detail line never shifts the art
    }
}
