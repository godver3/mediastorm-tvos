import AetherEngine
import os
import UIKit

/// Seek-preview thumbnails for one playback session, from the backend's thumbnail API
/// (Seekr's pre-made set first, the server's own ffmpeg generation as the fallback).
///
/// Mirrors the Expo player's `usePlaybackThumbnails`: read the status straight away (cached
/// sets come back immediately), ask for a Seekr-only start, and only if Seekr misses ask
/// the server to generate them, which reads the source; on a WebDAV (usenet) path that
/// waits until playback has run 15 s and is not buffering. Polls every 2 s while pending.
@MainActor
final class PlaybackThumbnails {
    struct Thumbnail: Equatable {
        let time: Double
        let url: URL
    }

    /// Times ascending.
    private(set) var thumbnails: [Thumbnail] = []
    /// Called on the main actor whenever the list grows.
    var onChange: (() -> Void)?

    private let api = APIClient.shared
    private let path: String
    private let request: PlaybackRequest
    private let log = AppLog(category: "thumbnails")
    private var task: Task<Void, Never>?
    private let images = NSCache<NSURL, UIImage>()
    private var loading: [URL: Task<UIImage?, Never>] = [:]

    /// Session facts the start request needs; read when the start is sent.
    struct Context {
        var duration: Double
        var playbackTime: Double
        var isBuffering: Bool
        var format: VideoFormat
        var dvProfile: Int?
        var chapterTimes: [Double]
    }

    init(path: String, request: PlaybackRequest) {
        self.path = path
        self.request = request
        images.countLimit = 60
    }

    /// Begins polling / starting generation. `context` is re-read on every attempt.
    func start(context: @escaping @MainActor () -> Context) {
        guard task == nil else { return }
        task = Task { [weak self] in await self?.run(context: context) }
    }

    func cancel() {
        task?.cancel()
        task = nil
        loading.values.forEach { $0.cancel() }
        loading = [:]
    }

    // MARK: Lookup

    /// The thumbnail at or just before `time` (the frame a seek there would land near).
    func index(at time: Double) -> Int? {
        guard !thumbnails.isEmpty else { return nil }
        var lo = 0, hi = thumbnails.count - 1
        if time <= thumbnails[0].time { return 0 }
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if thumbnails[mid].time <= time { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    func cachedImage(at index: Int) -> UIImage? {
        guard thumbnails.indices.contains(index) else { return nil }
        return images.object(forKey: thumbnails[index].url as NSURL)
    }

    /// Loads the image at `index` (with the API's auth headers), prefetching its neighbours.
    func image(at index: Int) async -> UIImage? {
        guard thumbnails.indices.contains(index) else { return nil }
        for offset in [-2, -1, 1, 2] where thumbnails.indices.contains(index + offset) {
            _ = load(thumbnails[index + offset].url)
        }
        return await load(thumbnails[index].url).value
    }

    private func load(_ url: URL) -> Task<UIImage?, Never> {
        if let cached = images.object(forKey: url as NSURL) { return Task { cached } }
        if let pending = loading[url] { return pending }
        var req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        // Bearer + X-Profile-Unlock in headers; the backend also takes `token=` on these
        // image URLs, but headers keep the session token out of URLs.
        for (field, value) in api.mediaHeaders { req.setValue(value, forHTTPHeaderField: field) }
        let fetch = req
        let task = Task { [weak self] () -> UIImage? in
            let image: UIImage? = await Task.detached(priority: .userInitiated) {
                guard let (data, response) = try? await URLSession.shared.data(for: fetch),
                      (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                return UIImage(data: data)?.preparingForDisplay()
            }.value
            guard let self else { return image }
            self.loading[url] = nil
            if let image { self.images.setObject(image, forKey: url as NSURL) }
            return image
        }
        loading[url] = task
        return task
    }

    // MARK: Status / start loop

    private func run(context: @MainActor () -> Context) async {
        var seekrRequested = false
        var generationRequested = false
        var lastStatus = ""
        let pressureSensitive = path.hasPrefix("/webdav/") || path.hasPrefix("webdav/")

        while !Task.isCancelled {
            let status: VideoThumbnailStatus
            do {
                status = try await api.videoThumbnailsStatus(path: path)
            } catch {
                if Task.isCancelled { return }
                log.error("status failed: \(error.localizedDescription)")
                try? await Task.sleep(for: .seconds(2))
                continue
            }
            if Task.isCancelled { return }
            let count = status.thumbnails?.count ?? 0
            if status.status != lastStatus {
                log.info("status \(status.status) count=\(count)")
                lastStatus = status.status
            }
            // An empty transient answer must not erase thumbnails already shown.
            if count > 0 { apply(status.thumbnails ?? []) }

            let ctx = context()
            if status.status == "disabled" { return }
            if status.status == "ready" && count > 0 { return }
            // Generation was asked for and has settled without a usable set (failed).
            if generationRequested && status.status != "generating" && status.status != "pending" { return }
            let canGenerate = !pressureSensitive || (ctx.playbackTime >= 15 && !ctx.isBuffering)
            if status.status != "generating", !generationRequested, ctx.duration >= 120,
               !seekrRequested || canGenerate {
                let seekrOnly = !seekrRequested
                if seekrOnly { seekrRequested = true } else { generationRequested = true }
                do {
                    let started = try await api.startVideoThumbnails(path: path, duration: ctx.duration,
                                                                     options: startOptions(ctx, seekrOnly: seekrOnly))
                    log.info("start (seekrOnly=\(seekrOnly)) -> \(started.status)")
                    if started.status == "disabled" { return }
                } catch {
                    log.error("start failed: \(error.localizedDescription)")
                    if !seekrOnly { return }
                }
                continue  // poll straight away
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func startOptions(_ ctx: Context, seekrOnly: Bool) -> APIClient.ThumbnailStartOptions {
        let t = request.title
        let isDV = ctx.format == .dolbyVision
        return APIClient.ThumbnailStartOptions(
            seekrOnly: seekrOnly,
            imdbID: t.imdbID,
            tmdbID: t.tmdbID,
            mediaType: request.isEpisode ? "episode" : "movie",
            season: request.episode?.season,
            episode: request.episode?.episode,
            hdr: ctx.format == .hdr10 || ctx.format == .hdr10Plus || ctx.format == .hlg,
            dolbyVision: isDV,
            dvProfile: isDV ? ctx.dvProfile.map { String(format: "dvhe.%02d", $0) } : nil,
            chapterTimes: ctx.chapterTimes
        )
    }

    private func apply(_ items: [VideoThumbnailStatus.Item]) {
        let next = items.compactMap { item in
            api.thumbnailImageURL(item.url).map { Thumbnail(time: item.timeSec, url: $0) }
        }.sorted { $0.time < $1.time }
        guard next != thumbnails else { return }
        thumbnails = next
        onChange?()
    }
}
