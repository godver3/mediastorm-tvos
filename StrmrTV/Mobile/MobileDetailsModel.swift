#if os(iOS)
import SwiftUI

/// The phone details page's state and logic, ported from the TV page's `DetailsView`
/// extensions (Loading, Library, Tracks, WatchState, Ordering): one `/details-bundle` load,
/// the libraries lookup, resume decisions and the requests handed to `PlaybackCoordinator`.
/// The TV page keeps its own copy in View state; both build requests with `DetailsRequest`.
///
/// One difference from the TV page, as on the Expo phone page: tapping an episode selects it
/// (`selectedEpisode`) and the primary button, Choose Source and the watch-state menu then
/// target it; tapping the selected episode again plays it.
@MainActor
final class MobileDetailsModel: ObservableObject {
    let target: DetailsTarget
    /// Fixed per page, so the loading art order doesn't reshuffle between plays.
    let artSeed = UInt64.random(in: .min ... .max)

    @Published var title: Title?
    @Published var seasons: [Season] = []
    @Published var selectedSeason: Int?
    @Published var upNext: EpisodeRef?
    /// The server's up-next episode, else the first one (the spoiler settings' "current").
    @Published var primaryEpisode: Episode?
    /// The episode tapped in the list; nil follows `primaryEpisode`.
    @Published var selectedEpisodeID: String?
    @Published var airedRegularEpisodes: [Episode] = []
    @Published var watchStateSeasons = WatchStateSeasons([])
    @Published var resume: ResumeState?
    @Published var loadError: String?
    @Published var serverInWatchlist: Bool?
    @Published var movieWatched: Bool?
    @Published var contentPreference: ContentPreference?
    /// Watched changes made here, shown until the reload after the write lands (by episode ID).
    @Published var watchedOverrides: [String: Bool] = [:]
    @Published var similar: [Title] = []
    @Published var collectionMovies: [Title] = []
    private var loadedCollectionID: Int?
    @Published var orderings: [SeriesOrdering] = []
    @Published var activeOrdering: String?
    @Published var pickedOrdering: String?
    @Published var libraryVersions: LibraryVersions?
    private var libraryLookup: Task<LibraryVersions?, Never>?
    /// Audio & Subtitles picks for the prequeued stream, by its stream path.
    @Published var prequeueOverrides: (streamPath: String?, overrides: ManualTrackOverrides) = (nil, ManualTrackOverrides())
    @Published var prequeueTrackPreferences = ManualTrackPreferences()

    // Presentation
    @Published var sourcePicker: SourceTarget?
    @Published var pendingSource: PendingSource?
    @Published var versionsPicker: VersionsTarget?
    @Published var pendingVersion: PendingVersion?
    @Published var showsPrequeueTracks = false
    /// Download / Download Season's release picker (`+Downloads`).
    @Published var downloadRequest: DownloadRequest?

    let trailer = TrailerController()
    private let playback = PlaybackCoordinator.shared

    struct SourceTarget: Identifiable {
        let episode: Episode?
        var id: String { episode?.id ?? "movie" }
    }

    struct PendingSource: Identifiable {
        let id = UUID()
        let source: SourceResult
        let tracks: ManualTrackPick?
        let episode: Episode?
        let resumeAt: StartPoint
    }

    struct VersionsTarget: Identifiable {
        let episode: Episode?
        /// Set when Play opened the list: a pick plays from here, and Stream Instead is offered.
        var play: PlayIntent?
        var id: String { (episode?.id ?? "movie") + (play == nil ? "" : ":play") }
    }

    struct PlayIntent { let start: StartPoint? }

    struct PendingVersion: Identifiable {
        let id = UUID()
        let version: LibraryVersion
        let episode: Episode?
        let resumeAt: StartPoint
    }

    init(target: DetailsTarget) {
        self.target = target
    }

    // MARK: Derived

    var visibleSeasons: [Season] {
        seasons.filter { $0.number > 0 } + seasons.filter { $0.number == 0 }
    }

    var currentSeason: Season? {
        visibleSeasons.first { $0.number == selectedSeason } ?? visibleSeasons.first
    }

    /// The episode the primary button plays: the one tapped, else up next.
    var activeEpisode: Episode? {
        if let selectedEpisodeID {
            for season in seasons {
                if let match = season.episodes.first(where: { $0.id == selectedEpisodeID }) { return match }
            }
        }
        return primaryEpisode
    }

    var overview: String? {
        let text = title?.overview ?? target.overview
        return text?.isEmpty == false ? text : nil
    }

    var backdropURL: String? { title?.backdrop?.url ?? target.backdropURL }

    /// Where to resume, per the server's `resume.eligible` decision (no client thresholds).
    func resumePoint(_ episode: Episode?) -> StartPoint? {
        guard let episode else { return resume?.startPoint }
        if let own = episode.resume { return own.startPoint }
        if let upNext, DetailsView.isUpNext(episode, upNext) { return resume?.startPoint }
        return nil
    }

    func resumeFraction(_ episode: Episode?) -> Double {
        guard let episode else { return resume?.fraction ?? 0 }
        if let own = episode.resume { return own.fraction }
        if let upNext, DetailsView.isUpNext(episode, upNext) { return resume?.fraction ?? 0 }
        return 0
    }

    /// An episode row's progress; marking it watched or unwatched clears it on the server.
    func progress(_ episode: Episode) -> Double {
        guard isWatched(episode) == (episode.watched == true) else { return 0 }
        if let own = episode.resume { return own.eligible ? own.fraction : 0 }
        if let upNext, DetailsView.isUpNext(episode, upNext), resume?.eligible == true { return resume?.fraction ?? 0 }
        return 0
    }

    /// The primary button's episode, resume point and label.
    var primaryTarget: (episode: Episode?, start: StartPoint?, label: String)? {
        if target.isMovie {
            if let start = resumePoint(nil) { return (nil, start, String(localized: "Resume")) }
            return (nil, nil, String(localized: "Play"))
        }
        guard let ep = activeEpisode else { return nil }
        if let start = resumePoint(ep) { return (ep, start, String(localized: "Resume \(ep.code)")) }
        return (ep, nil, String(localized: "Play \(ep.code)"))
    }

    func isWatched(_ episode: Episode) -> Bool {
        watchedOverrides[episode.id] ?? (episode.watched == true)
    }

    var seriesWatchState: WatchStateEye.State {
        let watched = airedRegularEpisodes.reduce(0) { $0 + (isWatched($1) ? 1 : 0) }
        if watched == 0 { return .none }
        return watched == airedRegularEpisodes.count ? .complete : .partial
    }

    var isKids: Bool { AppSession.shared.profile?.isKidsProfile == true }

    var cast: [CastMember] {
        var seen = Set<Int>()
        return (title?.credits?.cast ?? []).filter { seen.insert($0.id).inserted }.prefix(20).map { $0 }
    }

    // MARK: Loading

    func load() async {
        startLibraryLookup()
        async let spoilerSettings: Void = target.isMovie ? () : SpoilerSettingsStore.shared.refresh()
        do {
            let bundle = try await APIClient.shared.detailsBundle(target, seasonType: pickedOrdering)
            if target.isMovie {
                guard let movie = bundle.movieDetails else { throw APIError.notReady("Details unavailable") }
                title = movie
            } else {
                guard let details = bundle.seriesDetails else { throw APIError.notReady("Details unavailable") }
                await spoilerSettings
                title = details.title
                seasons = details.seasons
                orderings = details.availableOrderings ?? []
                activeOrdering = details.activeOrdering
                upNext = bundle.upNextEpisode
                primaryEpisode = DetailsView.findPrimaryEpisode(in: details.seasons, upNext: bundle.upNextEpisode)
                airedRegularEpisodes = details.seasons.filter { $0.number > 0 }.flatMap(\.episodes)
                    .filter { $0.episodeNumber > 0 && ReleaseBadge.forEpisode(airDate: $0.airedDate) == nil }
                watchStateSeasons = WatchStateSeasons(details.seasons)
                if selectedSeason == nil { selectedSeason = primaryEpisode?.seasonNumber }
            }
            similar = DetailsView.unique(bundle.similar ?? [])
            trailer.prepare(bundle.trailers?.primary)
            // The phone plays trailers full screen only: no backdrop autoplay under the header.
            trailer.dismiss("phone")
            resume = bundle.resume
            serverInWatchlist = bundle.inWatchlist
            movieWatched = bundle.watched
            contentPreference = bundle.contentPreference
            watchedOverrides = [:]
            loadError = nil
            await loadCollection()
        } catch {
            if title == nil, !error.isCancellation { loadError = error.localizedDescription }
        }
    }

    private func loadCollection() async {
        guard let collection = title?.collection, collection.id != loadedCollectionID else { return }
        loadedCollectionID = collection.id
        collectionMovies = (try? await APIClient.shared.collectionMovies(id: collection.id)).map(DetailsView.unique) ?? []
    }

    /// Looks the title up in the libraries once per page.
    private func startLibraryLookup() {
        guard libraryLookup == nil else { return }
        let target = target
        let lookup = Task { () -> LibraryVersions? in
            guard let matches = try? await APIClient.shared.libraryMatches(for: target) else { return nil }
            let versions = LibraryVersions(matches: matches)
            return versions.isEmpty ? nil : versions
        }
        libraryLookup = lookup
        Task { libraryVersions = await lookup.value }
    }

    /// The copies of a movie (no episode) or of one episode.
    func libraryVersions(for episode: Episode?) -> [LibraryVersion] {
        guard let libraryVersions else { return [] }
        guard let episode else { return target.isMovie ? libraryVersions.movie : [] }
        return libraryVersions.versions(season: episode.seasonNumber, episode: episode.episodeNumber)
    }

    var primaryVersions: [LibraryVersion] {
        libraryVersions(for: target.isMovie ? nil : activeEpisode)
    }

    // MARK: Requests

    func request(_ episode: Episode?, from start: StartPoint?) -> PlaybackRequest {
        DetailsRequest.make(target: target, title: title, seasons: seasons, episode: episode,
                            start: start, seed: artSeed, library: libraryVersions)
    }

    /// Play, through the library when it has the movie or episode: one copy plays, several
    /// open Versions. A tap while the lookup still runs waits for it.
    func play(_ episode: Episode?, from start: StartPoint?) {
        guard libraryVersions == nil, let lookup = libraryLookup else {
            return playOrAsk(episode, from: start, library: libraryVersions)
        }
        Task { playOrAsk(episode, from: start, library: await lookup.value) }
    }

    private func playOrAsk(_ episode: Episode?, from start: StartPoint?, library: LibraryVersions?) {
        let copies = target.isMovie || episode != nil
            ? library?.versions(season: episode?.seasonNumber, episode: episode?.episodeNumber) ?? [] : []
        if copies.count > 1 {
            versionsPicker = VersionsTarget(episode: episode, play: PlayIntent(start: start))
            return
        }
        var request = request(episode, from: start)
        request.library = library
        playback.play(request, picks: prequeuePick)
    }

    /// Stream Instead, from the list Play opened: the prequeue, with no library copy.
    func streamInstead(_ episode: Episode?, from start: StartPoint?) {
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            var request = request(episode, from: start)
            request.library = nil
            playback.play(request, picks: prequeuePick)
        }
    }

    func playPrimary() {
        if let primary = primaryTarget { play(primary.episode, from: primary.start) }
    }

    /// Shuffle (the Expo More menu): a random aired episode of the show or of one season,
    /// with the rest of them, shuffled, as what Next Episode plays.
    func shuffle(season: Season?) {
        let pool = (season.map { [$0] } ?? seasons.filter { $0.number > 0 }).flatMap(\.episodes)
            .filter { ReleaseBadge.forEpisode(airDate: $0.airedDate) == nil }
        guard let first = pool.randomElement() else { return }
        var request = request(first, from: nil)
        request.following = pool.filter { $0.id != first.id }.shuffled().map(DetailsRequest.episodeInfo)
        playback.play(request, picks: nil)
    }

    // MARK: Manual sources and versions

    func chooseSource(for episode: Episode?) {
        sourcePicker = SourceTarget(episode: target.isMovie ? nil : episode)
    }

    /// After a manual pick: offer Resume / Start Over when there is a resume point.
    func choose(_ source: SourceResult, tracks: ManualTrackPick?, episode: Episode?) {
        Task {
            // Let the sheet finish going away first.
            try? await Task.sleep(for: .milliseconds(400))
            if let resumeAt = resumePoint(episode) {
                pendingSource = PendingSource(source: source, tracks: tracks, episode: episode, resumeAt: resumeAt)
            } else {
                playSource(source, tracks: tracks, episode: episode, from: nil)
            }
        }
    }

    func playSource(_ source: SourceResult, tracks: ManualTrackPick?, episode: Episode?, from start: StartPoint?) {
        playback.play(request(episode, from: start), source: source, tracks: tracks)
    }

    func pickVersion(_ version: LibraryVersion, episode: Episode?, play: PlayIntent? = nil) {
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            if let play {
                playVersion(version, episode: episode, from: play.start)
            } else if let resumeAt = resumePoint(episode) {
                pendingVersion = PendingVersion(version: version, episode: episode, resumeAt: resumeAt)
            } else {
                playVersion(version, episode: episode, from: nil)
            }
        }
    }

    func playVersion(_ version: LibraryVersion, episode: Episode?, from start: StartPoint?) {
        playback.playLibrary(request(episode, from: start), version: version)
    }
}
#endif
