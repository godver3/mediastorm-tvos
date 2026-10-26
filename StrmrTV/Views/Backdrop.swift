import SwiftUI
import UIKit

/// Full-bleed backdrop that cross-fades between images and keeps the previous one on
/// screen until the next has loaded, so changing `url` never flashes black or affects
/// layout (it is a fixed-size background, sized by its container).
struct Backdrop: View {
    let url: URL?
    /// Cross-fade from the previous image when `url` changes.
    var fade: Double = 0.35
    /// How long a new backdrop not yet in memory waits before loading, for one that
    /// follows focus: a fast swipe then fetches and decodes only where it stops, not one
    /// full-screen image per card passed.
    var settle: Duration = .zero

    @State private var image: UIImage?

    var body: some View {
        Color.black
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                        .id(image)
                }
            }
            .clipped()
            .task(id: url) { await load() }
            .accessibilityHidden(true)
    }

    private func load() async {
        // No art (a streaming service's hero): fade to black rather than keep the last.
        guard let url else {
            if image != nil { withAnimation(.easeInOut(duration: fade)) { image = nil } }
            return
        }
        let size = UIScreen.main.bounds.size
        if settle > .zero, ImagePipeline.cached(url, size: size, mode: .fill) == nil {
            try? await Task.sleep(for: settle)
            guard !Task.isCancelled else { return }
        }
        // Decoded off the main thread: a lazily decoded backdrop stalled the focus move
        // that brought it in.
        guard let loaded = await ImagePipeline.load(url, size: size, mode: .fill,
                                                     scale: ImagePipeline.scale),
              !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: fade)) { image = loaded }
    }
}
