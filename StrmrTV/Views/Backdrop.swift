import CoreImage
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
    /// Shows a blurred copy, rendered once per image. A live `.blur` over the full screen
    /// redrew on every frame the rows scrolled over it, which made the details page lag.
    var blurred = false

    @State private var image: UIImage?
    /// The blurred copy and the image it was made from.
    @State private var blurredCopy: (source: UIImage, image: UIImage)?

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
            .overlay {
                if let blurredCopy, blurredCopy.source === image {
                    Image(uiImage: blurredCopy.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(blurred ? 1 : 0)
                }
            }
            .clipped()
            .task(id: url) { await load() }
            .task(id: BlurKey(image: image, wanted: blurred)) { await loadBlurred() }
            .accessibilityHidden(true)
    }

    private struct BlurKey: Equatable {
        let image: UIImage?
        let wanted: Bool
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

    /// Blurs the current image the first time it is wanted; kept until the image changes.
    private func loadBlurred() async {
        guard blurred, let image, blurredCopy?.source !== image else { return }
        let result = await Task.detached(priority: .userInitiated) { Self.blur(image) }.value
        guard let result, !Task.isCancelled, self.image === image else { return }
        // Fades in if focus already went below the fold while it rendered.
        withAnimation(.easeInOut(duration: 0.35)) { blurredCopy = (image, result) }
    }

    private static let context = CIContext()

    /// A 40 pt Gaussian blur, matching the page's former `.blur(radius: 40)`. Done at a
    /// quarter size, which looks the same once blurred and is far cheaper.
    nonisolated private static func blur(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let downscale: CGFloat = 0.25
        let input = CIImage(cgImage: cg)
            .transformed(by: CGAffineTransform(scaleX: downscale, y: downscale))
        let radius = 40 * image.scale * downscale
        let output = input.clampedToExtent()
            .applyingGaussianBlur(sigma: radius)
            .cropped(to: input.extent)
        guard let rendered = context.createCGImage(output, from: input.extent) else { return nil }
        return UIImage(cgImage: rendered)
    }
}
