import SwiftUI
import UIKit

/// Loads artwork, decodes it off the main thread at the size it is drawn, and keeps
/// the result in memory. `UIImage(data:)` defers decoding to the first draw, which
/// lands on the main thread and dropped frames on every focus move that brought in new
/// art; `AsyncImage` also has no memory cache, so a lazy row re-fetched and re-decoded
/// every card it scrolled back to.
enum ImagePipeline {
    /// NSCache is thread-safe.
    nonisolated(unsafe) private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 200 << 20
        return cache
    }()

    /// Loads under way, so a card that appears while its art is being prefetched waits
    /// for that load instead of fetching and decoding it a second time.
    /// Guarded by `inFlightLock`.
    nonisolated(unsafe) private static var inFlight: [String: Task<UIImage?, Never>] = [:]
    private static let inFlightLock = NSLock()

    @MainActor static var scale: CGFloat { UIScreen.main.scale }

    private static func key(_ url: URL, _ size: CGSize, _ mode: ContentMode) -> NSString {
        "\(url.absoluteString)|\(Int(size.width))x\(Int(size.height))|\(mode == .fill ? "fill" : "fit")" as NSString
    }

    /// The decoded image, if it is already in memory.
    static func cached(_ url: URL?, size: CGSize, mode: ContentMode) -> UIImage? {
        guard let url else { return nil }
        return cache.object(forKey: key(url, size, mode))
    }

    /// Fetches (HTTP cache first), then decodes at the pixel size that covers (`fill`) or
    /// fits in (`fit`) `size` points at `scale` pixels per point. Never scales up.
    static func load(_ url: URL, size: CGSize, mode: ContentMode, scale: CGFloat,
                     priority: TaskPriority? = nil) async -> UIImage? {
        let key = key(url, size, mode)
        if let hit = cache.object(forKey: key) { return hit }
        let name = key as String
        let task = inFlightLock.withLock {
            if let running = inFlight[name] { return running }
            let task = Task(priority: priority) {
                let image = await fetch(url, key: name, size: size, mode: mode, scale: scale)
                inFlightLock.withLock { _ = inFlight.removeValue(forKey: name) }
                return image
            }
            inFlight[name] = task
            return task
        }
        // Waiting from a higher priority (a card on screen joining a prefetch) raises the
        // load's priority to match.
        return await task.value
    }

    /// Warms the cache for art about to be drawn at `size`, at low priority.
    @MainActor static func prefetch(_ url: URL?, size: CGSize, mode: ContentMode = .fill) {
        guard let url, cached(url, size: size, mode: mode) == nil else { return }
        let scale = scale
        Task.detached(priority: .utility) {
            _ = await load(url, size: size, mode: mode, scale: scale, priority: .utility)
        }
    }

    private static func fetch(_ url: URL, key: String, size: CGSize, mode: ContentMode,
                              scale: CGFloat) async -> UIImage? {
        #if DEBUG
        // `-StrmrImageDelay <seconds>` slows every load, to see art arrive under focus.
        let delay = UserDefaults.standard.double(forKey: "StrmrImageDelay")
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
        #endif
        let request: URLRequest
        if url.scheme == ServerArtwork.scheme {
            guard let authorized = await ServerArtwork.request(for: url) else { return nil }
            request = authorized
        } else {
            request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        }
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let source = UIImage(data: data) else { return nil }

        let pixels = source.size.applying(.init(scaleX: source.scale, y: source.scale))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let ratios = (target.width / max(pixels.width, 1), target.height / max(pixels.height, 1))
        let factor = min(mode == .fill ? max(ratios.0, ratios.1) : min(ratios.0, ratios.1), 1)
        let prepared: UIImage?
        if factor < 1 {
            prepared = await source.byPreparingThumbnail(ofSize: CGSize(width: (pixels.width * factor).rounded(),
                                                                        height: (pixels.height * factor).rounded()))
        } else {
            prepared = await source.byPreparingForDisplay()
        }
        guard let decoded = prepared else { return nil }
        let bytes = Int(decoded.size.width * decoded.scale * decoded.size.height * decoded.scale * 4)
        cache.setObject(decoded, forKey: key as NSString, cost: bytes)
        return decoded
    }
}

/// A remote image drawn at a fixed size through `ImagePipeline`. A card rebuilt by a
/// lazy row shows its cached image at once instead of flashing the placeholder.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    let size: CGSize
    var contentMode: ContentMode = .fill
    /// Where a `fit` image sits in the frame.
    var alignment: Alignment = .center
    /// Shown while loading (`false`) and when the load failed or there is no URL (`true`).
    @ViewBuilder let placeholder: (_ failed: Bool) -> Placeholder

    @State private var image: UIImage?
    @State private var failed = false

    init(url: URL?, size: CGSize, contentMode: ContentMode = .fill, alignment: Alignment = .center,
         @ViewBuilder placeholder: @escaping (_ failed: Bool) -> Placeholder) {
        self.url = url
        self.size = size
        self.contentMode = contentMode
        self.alignment = alignment
        self.placeholder = placeholder
        _image = State(initialValue: ImagePipeline.cached(url, size: size, mode: contentMode))
    }

    var body: some View {
        ZStack(alignment: alignment) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(width: size.width, height: size.height, alignment: alignment)
                    .clipped()
            } else {
                // Not clipped: a text fallback (a title name in a logo slot) may be wider
                // than the image frame.
                placeholder(failed || url == nil)
            }
        }
        .frame(width: size.width, height: size.height, alignment: alignment)
        .task(id: url) {
            guard let url else { return }
            if let image, image === ImagePipeline.cached(url, size: size, mode: contentMode) { return }
            image = nil
            failed = false
            let loaded = await ImagePipeline.load(url, size: size, mode: contentMode, scale: ImagePipeline.scale)
            guard !Task.isCancelled else { return }
            image = loaded
            failed = loaded == nil
        }
    }
}
