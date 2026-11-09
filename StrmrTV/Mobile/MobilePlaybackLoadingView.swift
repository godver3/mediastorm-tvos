#if os(iOS)
import SwiftUI

/// Stream-start screen: the title's art (its poster on a phone held upright, the backdrop
/// otherwise), its name and where resolving is up to.
struct MobilePlaybackLoadingView: View {
    let request: PlaybackRequest
    let stage: String
    let detail: String?
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black.ignoresSafeArea()
            GeometryReader { geo in
                RemoteImage(url: Artwork.url(art(portrait: geo.size.height > geo.size.width)),
                            size: geo.size) { _ in Color.black }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .overlay { LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .center, endPoint: .bottom) }
            }
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 8) {
                Text(request.title.name).font(.title.bold())
                if let ep = request.episode {
                    Text(ep.code + (ep.name.map { " · \($0)" } ?? "")).font(.headline).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    ProgressView()
                    Text(stage).font(.subheadline)
                }
                .padding(.top, 8)
                if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                    .padding(.top, 12)
            }
            .padding(24)
        }
    }

    /// A backdrop cropped to an upright phone is a narrow slice of it; the poster fits.
    private func art(portrait: Bool) -> String? {
        let backdrop = request.artwork.backdropURLs.first ?? request.title.backdropURL
        return portrait ? request.title.posterURL ?? backdrop : backdrop
    }
}
#endif
