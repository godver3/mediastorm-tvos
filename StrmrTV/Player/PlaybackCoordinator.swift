import AetherEngine
import AVKit
import SwiftUI
import UIKit

/// Resolves a source through the backend prequeue, then hands the stream to
/// AetherEngine behind a stock AVPlayerViewController.
@MainActor
final class PlaybackCoordinator: ObservableObject {
    static let shared = PlaybackCoordinator()

    /// The request being resolved; drives the loading art. Stays set until the player is on
    /// screen, so the art hands straight over to it.
    @Published private(set) var resolving: PlaybackRequest?
    @Published private(set) var resolvingStage = "Starting…"
    /// The release being tried, when the server names one.
    @Published private(set) var resolvingDetail: String?
    @Published var errorMessage: String?
    /// Bumped whenever a playback session ends, so screens can refresh progress.
    @Published private(set) var sessionsEnded = 0
    /// The details page's prequeue as it resolves, for its Audio & Subtitles button.
    @Published private(set) var warm: WarmPrequeue?

    private var resolveTask: Task<Void, Never>?
    /// Identifies the current resolve, so a cancelled one can't clear its successor.
    private var resolveID = UUID()
    private var previewSetting: (enabled: Bool, fetched: Date)?
    private var settings: (value: APIClient.PlaybackSettings, profile: String, fetched: Date)?
    /// A prequeue started ahead of time for the episode that plays next, keyed by
    /// `PlaybackRequest.prequeueKey`; `resolveStream` picks it up instead of starting over.
    private var prefetched: (key: String, prequeueID: String)?
    /// A prequeue started as a details page opened, for whatever the server would play there
    /// (the movie, or the series' next-up episode). `resolveStream` adopts it once; the title,
    /// profile and start time stay behind so re-opening the page doesn't search again.
    private var warmed: (titleID: String, profile: String, started: Date, prequeueID: Task<String?, Never>?)?
    private lazy var engine: AetherEngine? = {
        do {
            let engine = try AetherEngine()
            // Hand the audio session back when playback ends. Left active, it kept the
            // Siri Remote's dictation from working in Search after watching something.
            engine.deactivatesAudioSessionOnStop = true
            return engine
        } catch {
            errorMessage = "Player engine failed to start: \(error.localizedDescription)"
            return nil
        }
    }()

    private let api = APIClient.shared

    /// The one engine, for the live player.
    var sharedEngine: AetherEngine? { engine }

    /// Plays through the prequeue. `picks`, made on details for the stream its prequeue
    /// resolved, are laid over the server's selection when Play resolves that same stream.
    func play(_ request: PlaybackRequest, picks: PrequeuePick? = nil) {
        begin(request, stage: String(localized: "Searching…")) { [self] in
            let resolved = try await resolveStream(request)
            guard let path = resolved.streamPath else { throw APIError.notReady("Stream resolved without a path") }
            await TrackSettingsStore.shared.loadIfNeeded()
            let current = SourceSwitch.Current(releaseName: resolved.displayName, streamPath: path)
            if let picks {
                guard picks.applies(to: resolved) else {
                    SourceTracksModel.log.notice("details picks dropped: resolved a different stream")
                    return (path, TrackPreferences.overridden(resolved) ?? TrackPreferences(resolved), current)
                }
                return (path, picks.pick.preferences(over: resolved.trackSelection), current)
            }
            return (path, TrackPreferences.overridden(resolved) ?? TrackPreferences(resolved), current)
        }
    }

    /// Plays a source the user picked by hand, bypassing the automatic prequeue. `tracks`,
    /// picked from the source's probe with a long press, are laid over the server's selection
    /// and win over Settings › Playback's device overrides. `carry` (Switch Source in the player)
    /// re-picks the previous source's audio and subtitle languages from the new source's tracks.
    func play(_ request: PlaybackRequest, source: SourceResult, tracks manual: ManualTrackPick? = nil,
              carry: TrackCarry? = nil) {
        begin(request, stage: String(localized: "Preparing…"), carry: carry) { [self] in
            let resolved = try await api.resolveSource(source, titleID: request.title.titleID,
                                                       startOffset: request.startPosition)
            let current = SourceSwitch.Current(guid: source.id, releaseName: SourceSwitch.releaseName(source),
                                               streamPath: resolved.path)
            guard let manual else { return (resolved.path, TrackPreferences(selection: resolved.tracks), current) }
            await TrackSettingsStore.shared.loadIfNeeded()
            return (resolved.path, manual.preferences(over: resolved.tracks), current)
        }
    }

    /// Stops a resolve in flight (Menu on the loading art) and returns to the page underneath.
    func cancelResolve() {
        guard resolving != nil else { return }
        resolveTask?.cancel()
        resolveTask = nil
        resolveID = UUID()
        resolving = nil
        resolvingDetail = nil
    }

    private func begin(_ request: PlaybackRequest, stage: String, carry: TrackCarry? = nil,
                       resolve: @escaping @MainActor () async throws -> (path: String, tracks: TrackPreferences,
                                                                         source: SourceSwitch.Current)) {
        guard resolving == nil else { return }
        let id = UUID()
        resolveID = id
        resolving = request
        resolvingStage = stage
        resolvingDetail = nil
        resolveTask = Task {
            async let previews = previewThumbnailsEnabled()
            do {
                #if DEBUG
                // UI tests: `-StrmrResolveDelay <s>` holds the loading art up long enough to cancel.
                let delay = UserDefaults.standard.double(forKey: "StrmrResolveDelay")
                if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
                #endif
                let (path, tracks, source) = try await resolve()
                try Task.checkCancellation()
                guard resolveID == id else { return }
                guard let engine else { return finishResolve(id) }
                resolvingStage = String(localized: "Starting…")
                resolvingDetail = nil
                presentPlayer(engine: engine, request: request, path: path, tracks: tracks, source: source,
                              carry: carry, previewsEnabled: await previews) { self.finishResolve(id) }
            } catch is CancellationError {
                finishResolve(id)
            } catch {
                guard !Task.isCancelled, resolveID == id else { return }
                finishResolve(id)
                errorMessage = error.localizedDescription
            }
        }
    }

    private func finishResolve(_ id: UUID) {
        guard resolveID == id else { return }
        resolveTask = nil
        resolving = nil
        resolvingDetail = nil
    }

    /// The admin's preview-thumbnail switch, re-read at most every five minutes.
    private func previewThumbnailsEnabled() async -> Bool {
        if let previewSetting, Date().timeIntervalSince(previewSetting.fetched) < 300 { return previewSetting.enabled }
        let enabled = await api.previewThumbnailsEnabled()
        previewSetting = (enabled, Date())
        return enabled
    }

    /// The profile's credits auto-skip.
    func creditsAutoSkipEnabled() async -> Bool {
        await playbackSettings().creditsAutoSkip
    }

    /// The profile's playback settings, re-read at most every five minutes (or on a profile switch).
    private func playbackSettings() async -> APIClient.PlaybackSettings {
        let profile = api.profileID
        if let settings, settings.profile == profile,
           Date().timeIntervalSince(settings.fetched) < 300 { return settings.value }
        let value = await api.playbackSettings()
        settings = (value, profile, Date())
        SubtitleStyleStore.shared.adopt(value.subtitleStyle)
        return value
    }

    /// Reads the server's subtitle style now, so Settings shows the current one (playback
    /// reads it with the rest of the profile's settings).
    func refreshSubtitleStyle() async {
        settings = nil
        _ = await playbackSettings()
    }

    /// Starts resolving `request` on the server ahead of time (the player calls this near the
    /// end of an episode), so the next episode starts quickly. Failures are left for `play`.
    func prefetch(_ request: PlaybackRequest) {
        let key = request.prequeueKey
        guard prefetched?.key != key else { return }
        prefetched = (key, "")
        Task {
            do {
                let started = try await api.startPrequeue(prequeueBody(request))
                if prefetched?.key == key { prefetched = (key, started.prequeueId) }
            } catch {
                if prefetched?.key == key { prefetched = nil }
            }
        }
    }

    /// Starts resolving what `target`'s details page would play, as soon as it is opened, so
    /// Play starts quickly, unless the profile turned prequeue off (`disablePrequeue`). At most
    /// once per title and profile every ten minutes.
    func prewarm(_ target: DetailsTarget) {
        let profile = api.profileID
        if let warmed, warmed.titleID == target.titleID, warmed.profile == profile,
           Date().timeIntervalSince(warmed.started) < 600 { return }
        // No episode or start point: the server targets the series' next-up episode, and the
        // start offset only matters to HLS, which this client skips.
        let body = prequeueBody(PlaybackRequest(title: target, episode: nil, start: nil))
        warm = WarmPrequeue(titleID: target.titleID, profile: profile, phase: .resolving)
        let task = Task { [api] () -> String? in
            guard await self.playbackSettings().prequeueOnOpen,
                  let id = try? await api.startPrequeue(body).prequeueId else {
                self.settleWarm(target.titleID, profile, .unavailable)
                return nil
            }
            Task { await self.watchWarm(id, titleID: target.titleID, profile: profile) }
            return id
        }
        warmed = (target.titleID, profile, Date(), task)
    }

    /// Follows the details prequeue until it settles, for the page's Audio & Subtitles button.
    private func watchWarm(_ id: String, titleID: String, profile: String) async {
        let deadline = Date().addingTimeInterval(180)
        let log = AppLog(category: "prequeue")
        while Date() < deadline, warm?.titleID == titleID, warm?.profile == profile {
            do {
                let status = try await api.prequeueStatus(id)
                if status.status == "ready" {
                    log.notice("details prequeue \(id) ready: \(status.audioTracks?.count ?? 0) audio, "
                        + "\(status.subtitleTracks?.count ?? 0) subtitles")
                    return settleWarm(titleID, profile, .ready(status))
                }
                if status.status == "failed" || status.status == "expired" { break }
            } catch {
                log.error("details prequeue \(id) status failed: \(error.localizedDescription)")
            }
            try? await Task.sleep(for: .milliseconds(1500))
        }
        log.notice("details prequeue \(id) unavailable")
        settleWarm(titleID, profile, .unavailable)
    }

    private func settleWarm(_ titleID: String, _ profile: String, _ phase: WarmPrequeue.Phase) {
        guard warm?.titleID == titleID, warm?.profile == profile, case .resolving = warm?.phase else { return }
        warm?.phase = phase
    }

    /// The full-screen player is up (nothing SwiftUI can present over it).
    var isPresentingPlayer: Bool {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var vc = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let current = vc {
            if current is PlayerViewController { return true }
            vc = current.presentedViewController
        }
        return false
    }

    /// A stream is resolving or a player (VOD or live) is up: no background speed tests.
    var isBusy: Bool {
        resolving != nil || Self.topViewController().map { top in
            var vc: UIViewController? = top
            while let current = vc {
                if current is EnginePlayerViewController { return true }
                vc = current.presentingViewController
            }
            return false
        } ?? false
    }

    func playerDidClose() {
        sessionsEnded += 1
    }

    private func resolveStream(_ request: PlaybackRequest) async throws -> PrequeueStatus {
        if let prefetched, prefetched.key == request.prequeueKey, !prefetched.prequeueID.isEmpty {
            self.prefetched = nil
            do {
                return try await awaitPrequeue(prefetched.prequeueID)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Expired or failed while the last episode played: start a fresh one.
            }
        }
        if let warmed, warmed.titleID == request.title.titleID, warmed.profile == api.profileID,
           let pending = warmed.prequeueID {
            self.warmed?.prequeueID = nil
            if let id = await pending.value {
                do {
                    return try await awaitPrequeue(id, expecting: request.episode)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // A different episode than the one asked for, or expired / failed: start fresh.
                }
            }
        }
        let started = try await api.startPrequeue(prequeueBody(request))
        return try await awaitPrequeue(started.prequeueId)
    }

    private func prequeueBody(_ request: PlaybackRequest) -> [String: Any] {
        let t = request.title
        var body: [String: Any] = [
            "titleId": t.titleID,
            "titleName": t.name,
            "mediaType": t.isMovie ? "movie" : "series",
            "userId": api.profileID,
            "clientId": Config.clientID,
            "reason": "details",
            "skipHLS": true,
        ]
        if let v = t.imdbID { body["imdbId"] = v }
        if let v = t.tmdbID { body["tmdbId"] = v }
        if let v = t.tvdbID { body["tvdbId"] = v }
        if let v = t.year { body["year"] = v }
        if let ep = request.episode {
            body["seasonNumber"] = ep.season
            body["episodeNumber"] = ep.episode
            if let abs = ep.absolute, abs > 0 { body["absoluteEpisodeNumber"] = abs }
        }
        if let start = request.startPosition { body["startOffset"] = start }
        return body
    }

    /// Polls a prequeue until its stream is ready. With `episode`, gives up straight away if the
    /// prequeue is resolving a different one.
    private func awaitPrequeue(_ id: String, expecting episode: PlaybackRequest.EpisodeInfo? = nil) async throws -> PrequeueStatus {
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            try Task.checkCancellation()
            let status = try await api.prequeueStatus(id)
            if let episode, status.targetEpisode?.seasonNumber != episode.season
                || status.targetEpisode?.episodeNumber != episode.episode {
                throw APIError.notReady("Prequeue is for a different episode")
            }
            switch status.status {
            case "ready":
                guard let path = status.streamPath, !path.isEmpty else {
                    throw APIError.notReady("Stream resolved without a path")
                }
                return status
            case "failed", "expired":
                throw APIError.notReady(status.error ?? "No playable stream found")
            default:
                guard resolving != nil else { break }
                let (stage, detail) = Self.describe(status)
                resolvingStage = stage
                resolvingDetail = detail
            }
            try await Task.sleep(for: .milliseconds(750))
        }
        throw APIError.notReady("Timed out waiting for a stream")
    }

    /// A friendly line for the prequeue's stage, plus the release being tried when there is one.
    private static func describe(_ s: PrequeueStatus) -> (String, String?) {
        let detail = s.progressDetail.flatMap { $0.isEmpty ? nil : $0 }
        switch s.progressStage ?? s.status {
        case "queued", "metadata":
            return (String(localized: "Starting…"), nil)
        case "searching":
            return (String(localized: "Searching…"), nil)
        case "ranking", "preparing_candidates":
            return (String(localized: "Ranking…"), nil)
        case "resolving_candidate", "waiting_provider":
            return (String(localized: "Fetching…"), detail)
        case "validating_candidate":
            return (String(localized: "Checking…"), detail)
        case "analyzing_media", "probing", "selecting_tracks":
            return (String(localized: "Inspecting…"), nil)
        case "preparing_playback":
            return (String(localized: "Preparing…"), nil)
        default:
            return (String(localized: "Searching…"), nil)
        }
    }

    /// Presents the player over the loading art; `completion` runs once it is on screen
    /// (or right away when there is nothing to present on).
    private func presentPlayer(engine: AetherEngine, request: PlaybackRequest, path: String,
                               tracks: TrackPreferences, source: SourceSwitch.Current, carry: TrackCarry?,
                               previewsEnabled: Bool, completion: @escaping () -> Void) {
        guard let presenter = Self.topViewController() else { return completion() }
        let url = api.streamURL(for: path, metadata: request.streamMetadataQuery)
        let player = PlayerViewController(engine: engine, request: request, url: url,
                                          streamPath: path, tracks: tracks, previewsEnabled: previewsEnabled)
        player.currentSource = source
        player.trackCarry = carry
        presenter.present(player, animated: true, completion: completion)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
