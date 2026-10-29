import SwiftUI

struct DetailsView: View {
    // State and helpers are internal, not private: the page is split across
    // DetailsView+Actions.swift and DetailsView+Rows.swift.
    let target: DetailsTarget

    @ObservedObject var playback = PlaybackCoordinator.shared
    @ObservedObject var spoilers = SpoilerSettingsStore.shared
    @EnvironmentObject var watchlist: WatchlistStore
    @EnvironmentObject var customLists: CustomListsStore
    @EnvironmentObject var titles: TitleStateStore
    @Environment(\.dismiss) var dismiss
    @State var title: Title?
    /// Fixed per page, so the loading art order doesn't reshuffle between plays.
    @State var artSeed = UInt64.random(in: .min ... .max)
    @State var seasons: [Season] = []
    @State var selectedSeason: Int?
    @State var upNext: EpisodeRef?
    /// The episode the primary button plays: the server's up-next episode, else the first one.
    /// Stored, not computed: long series (One Piece) make a per-render search expensive.
    @State var primaryEpisode: Episode?
    /// Aired regular-season episodes, for the series watch-state eye (set on load).
    @State var airedRegularEpisodes: [Episode] = []
    /// The watch-state menu's seasons and their aired episodes (set on load). Built per render,
    /// it dated every episode on each focus move, which lagged a long series (Survivor).
    @State var watchStateSeasons = WatchStateSeasons([])
    /// Server resume decision for the movie, or for `upNext`.
    @State var resume: ResumeState?
    @State var loadError: String?
    /// The bundle's `inWatchlist` (nil on older servers); the store layers toggles on top.
    @State var serverInWatchlist: Bool?
    @State var watchlistBusy = false
    @State var watchlistError: String?
    /// The bundle's movie `watched` (nil on older servers or for series).
    @State var movieWatched: Bool?
    /// The bundle's per-title track languages, for the source picker's track defaults.
    @State var contentPreference: ContentPreference?
    /// Watched changes made here, shown until the reload after the write lands (by episode ID).
    @State var watchedOverrides: [String: Bool] = [:]
    @State var watchedBusy = false
    @State var watchedError: String?
    /// The More Options dialog (`DetailsView+More`).
    /// Source picker currently shown (movie, or a specific episode).
    @State var sourcePicker: SourcePickerTarget?
    /// A picked source waiting on the Resume / Start Over choice.
    @State var pendingSource: PendingSource?
    @FocusState var focus: DetailsFocus?
    /// Where focus last was in each row, for Up / Down back into it (`DetailsView+Focus`).
    @State var focusMemory = FocusMemory()
    /// More Like This, from the bundle.
    @State var similar: [Title] = []
    /// Movies: the collection's movies, and which collection they are for.
    @State var collectionMovies: [Title] = []
    @State var loadedCollectionID: Int?
    /// The overview shown whole over the page, blurred behind it.
    @State var showsFullOverview = false
    @StateObject var trailer = TrailerController()
    /// Focus is in the header (the page's first screen). Kept across focus going nil while a
    /// cover is up, so returning from the player doesn't scroll the page.
    @State var focusInHeader = true
    /// Audio & Subtitles picks for the prequeued stream, by its stream path (`DetailsView+Tracks`).
    @State var prequeueOverrides: (streamPath: String?, overrides: ManualTrackOverrides) = (nil, ManualTrackOverrides())
    @State var prequeueTrackPreferences = ManualTrackPreferences()
    @State var showPrequeueTracks = false
    /// The title's copies in the profile's libraries and the lookup for them (`DetailsView+Library`).
    @State var libraryVersions: LibraryVersions?
    @State var libraryLookup: Task<LibraryVersions?, Never>?
    @State var versionsPicker: VersionsTarget?
    @State var pendingVersion: PendingVersion?
    /// A menu is up (Watch State, Manage Lists, More Options, an episode's long press), for
    /// `menuOpen` and `load`.
    @State var systemMenuOpen = false
    /// Which secondary actions are in the row and which in More (`DetailsButtons`).
    @ObservedObject var buttons = DetailsButtonsStore.shared
    @State var customizingButtons = false

    enum DetailsAction: String, Hashable { case primary, startOver, versions, chooseSource, tracks, trailer, watchlist, lists, watched, more }

    /// Every focusable on the page, so moves between rows can be steered.
    enum DetailsFocus: Hashable {
        /// The overview, above the actions; focusable only when it is cut off.
        case overview
        case action(DetailsAction)
        case season(Int)
        case episode(String)
        /// A card in a related row, by title ID (cast: person ID).
        case related(RelatedRow, String)
        /// Holds focus while the header is faded over the backdrop trailer.
        case immersive

        var row: Row {
            switch self {
            case .overview: .overview
            case .action: .actions
            case .season: .seasons
            case .episode: .episodes
            case .related(let row, _): .related(row)
            case .immersive: .immersive
            }
        }
    }

    /// The page's two scroll stops: the first screen, and the rows below it.
    enum PageAnchor: Hashable { case header, rows }

    enum Row: Hashable { case overview, actions, seasons, episodes, related(RelatedRow), immersive }

    /// The rows under the episodes, in the Expo TV page's order.
    enum RelatedRow: Hashable { case collection, similar, cast }

    struct SourcePickerTarget: Identifiable {
        let episode: Episode?
        var id: String { episode?.id ?? "movie" }
    }

    struct PendingSource {
        let source: SourceResult
        /// Tracks picked with a long press in the source list.
        let tracks: ManualTrackPick?
        let episode: Episode?
        let resumeAt: StartPoint
    }

    // MARK: Derived state

    var visibleSeasons: [Season] {
        // Specials last, so the picker opens on real seasons.
        seasons.filter { $0.number > 0 } + seasons.filter { $0.number == 0 }
    }

    var currentSeason: Season? {
        visibleSeasons.first { $0.number == selectedSeason } ?? visibleSeasons.first
    }

    static func findPrimaryEpisode(in seasons: [Season], upNext: EpisodeRef?) -> Episode? {
        if let upNext {
            for season in seasons {
                if let match = season.episodes.first(where: { isUpNext($0, upNext) }) { return match }
            }
        }
        let firstSeason = seasons.filter { $0.number > 0 }.first ?? seasons.first
        return firstSeason?.episodes.first
    }

    static func isUpNext(_ episode: Episode, _ ref: EpisodeRef) -> Bool {
        if let a = episode.itemId, let b = ref.itemId { return a == b }
        return episode.seasonNumber == ref.seasonNumber && episode.episodeNumber == ref.episodeNumber
    }

    /// How far through the resume point is (0–1), for the primary button's fill.
    func resumeFraction(_ episode: Episode?) -> Double {
        guard let episode else { return resume?.fraction ?? 0 }
        if let own = episode.resume { return own.fraction }
        if let upNext, Self.isUpNext(episode, upNext) { return resume?.fraction ?? 0 }
        return 0
    }

    /// Where to resume, per the server's `resume.eligible` decision (no client thresholds).
    func resumePoint(_ episode: Episode?) -> StartPoint? {
        guard let episode else { return resume?.startPoint }
        if let own = episode.resume { return own.startPoint }
        if let upNext, Self.isUpNext(episode, upNext) { return resume?.startPoint }
        return nil
    }

    // MARK: Body

    var body: some View {
        ZStack {
            // Below the fold the backdrop blurs behind the rows, in step with the scroll. The
            // trailer is stopped by then, so it stays out of the blur.
            Backdrop(url: Artwork.url(title?.backdrop?.url ?? target.backdropURL), blurred: !focusInHeader)
                .overlay { TrailerBackdropVideo(trailer: trailer) }
                .overlay { Color.black.opacity(focusInHeader ? 0 : 0.2) }
                .animation(.easeInOut(duration: 0.35), value: focusInHeader)
                .overlay { DetailsBackdropShade(hidden: trailer.immersive) }
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        // First screen: the header anchored in the lower left, like the Apple TV
                        // app. Seasons and episodes start below the fold.
                        header
                            // Just enough room under the actions for the focus lift; the safe
                            // area already keeps them clear of the screen edge.
                            .padding(.bottom, 12)
                            .containerRelativeFrame(.vertical, alignment: .bottomLeading)
                            // Fades as it scrolls up, so the actions don't linger over the
                            // top edge above the seasons. A mask, not opacity: the focus engine
                            // skips transparent views, and Up has to reach the actions again.
                            // Outset past the header so it doesn't clip the actions' focus
                            // lift (Play sits on the header's left edge) or their captions.
                            .mask { Color.black.opacity(focusInHeader ? 1 : 0).padding(-60) }
                            .animation(.easeInOut(duration: 0.35), value: focusInHeader)
                            .id(PageAnchor.header)
                        VStack(alignment: .leading, spacing: 0) {
                            if !target.isMovie && !seasons.isEmpty {
                                episodesSection
                                    .padding(.top, 60)  // fully below the fold until focus moves down
                            }
                            relatedSections
                                .padding(.top, target.isMovie || seasons.isEmpty ? 60 : 30)
                                .padding(.bottom, 80)
                        }
                        .id(PageAnchor.rows)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 80)
                    .opacity(trailer.immersive ? 0 : 1)
                }
                .scrollClipDisabled()
                // The focus engine scrolls a focused action clear of the screen edge, which
                // floated the header up and the next row in. Scrolling is off while focus is in
                // the header, so the actions stay at the bottom; crossing the fold scrolls the
                // page by hand, since focus has already moved when scrolling comes back on.
                .scrollDisabled(focusInHeader)
                .onChange(of: focusInHeader) { _, inHeader in
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(inHeader ? PageAnchor.header : PageAnchor.rows, anchor: .top)
                    }
                }
            }
        }
        .disabled(showsFullOverview)
        .blur(radius: showsFullOverview ? 40 : 0)
        .overlay {
            if showsFullOverview, let overview {
                FullTextOverlay(title: target.name, text: overview) {
                    showsFullOverview = false
                    focus = .overview
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: showsFullOverview)
        // Scrolling down to the seasons collapses the tab bar, and a page popped back to
        // doesn't scroll to bring it back. Hidden here, SwiftUI restores it on the pop.
        .toolbar(.hidden, for: .tabBar)
        .defaultFocus($focus, .action(.primary))
        .onChange(of: focus) { old, new in steerFocus(from: old, to: new) }
        .modifier(DetailsTrailerModifier(trailer: trailer, focus: $focus, playbackStarting: playback.resolving != nil,
                                         menuOpen: menuOpen))
        .tracksMenuPresence($systemMenuOpen)
        // Not in the navigation destination: that runs during a view update, so its publish
        // re-ran every destination on the stack, and two details pages prewarming in turn
        // never settled (a page opened from More Like This froze the app).
        .onAppear { playback.prewarm(target) }
        .task { await load() }
        .onReceive(DeepLinkRouter.shared.$autoplayTitleID) { _ in autoplayIfRequested() }
        .onChange(of: playback.sessionsEnded) {
            // The picks were for the prequeue that just played.
            prequeueOverrides = (nil, ManualTrackOverrides())
            Task { await load() }
        }
        .fullScreenCover(isPresented: $showPrequeueTracks) { prequeueTracksPage }
        .fullScreenCover(isPresented: $customizingButtons) { DetailsButtonsSheet() }
        .modifier(libraryVersionsPresentation)
        .fullScreenCover(item: $sourcePicker) { picker in
            SourcePickerView(title: target, episode: picker.episode, contentPreference: contentPreference) { source, tracks in
                choose(source, tracks: tracks, episode: picker.episode)
            }
        }
        .confirmationDialog(
            pendingSource.map { pending in pending.episode.map { "\(target.name) · \($0.code)" } ?? target.name } ?? "",
            isPresented: Binding(get: { pendingSource != nil }, set: { if !$0 { pendingSource = nil } }),
            titleVisibility: .visible,
            presenting: pendingSource
        ) { pending in
            Button("Resume from \(pending.resumeAt.label)") {
                playSource(pending.source, tracks: pending.tracks, episode: pending.episode, from: pending.resumeAt)
            }
            Button("Start Over") {
                playSource(pending.source, tracks: pending.tracks, episode: pending.episode, from: nil)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Manual source selection

    /// After a manual pick: offer Resume / Start Over when there is a resume point.
    func choose(_ source: SourceResult, tracks: ManualTrackPick?, episode: Episode?) {
        if let resumeAt = resumePoint(episode) {
            // Let the picker's dismissal finish before presenting the dialog.
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                pendingSource = PendingSource(source: source, tracks: tracks, episode: episode, resumeAt: resumeAt)
            }
        } else {
            playSource(source, tracks: tracks, episode: episode, from: nil)
        }
    }

    func playSource(_ source: SourceResult, tracks: ManualTrackPick?, episode: Episode?, from start: StartPoint?) {
        playback.play(request(episode, from: start), source: source, tracks: tracks)
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 26) {
            // Waits briefly for the logo (from the card, else from details) instead of
            // showing the name first and swapping it out.
            TitleLogo(url: Artwork.logoURL(title?.logo?.url ?? target.logoURL),
                      pending: title == nil && loadError == nil,
                      size: CGSize(width: 640, height: 220)) {
                titleText.frame(width: 1000, alignment: .bottomLeading)
            }
            .accessibilityLabel(target.name)

            HStack(spacing: 20) {
                if let headerBadge { BadgeLabel(text: headerBadge.text, symbol: headerBadge.symbol) }
                Text(metadataLine).font(.system(size: 26, weight: .medium)).foregroundStyle(.secondary)
            }

            if let ratings = title?.ratings, !ratings.isEmpty { RatingsRow(ratings: ratings) }

            if let overview {
                // Up from the actions reaches it only when it is cut off; select shows it whole.
                ExpandableText(text: overview, lineLimit: 3, fontSize: 26, onlyWhenTruncated: true) {
                    showsFullOverview = true
                }
                .focused($focus, equals: .overview)
                .frame(maxWidth: 1000, alignment: .leading)
            }

            if let message = loadError ?? watchlistError ?? watchedError ?? trailer.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red)
            }

            actionButtons
                .padding(.top, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .focusSection()
                .defaultFocus($focus, .action(.primary), priority: .userInitiated)
        }
    }

    var overview: String? { title?.overview ?? target.overview }

    /// Whether a row is part of the first screen's header, where the page stays at the top.
    static func isHeader(_ row: Row) -> Bool {
        switch row {
        case .overview, .actions, .immersive: true
        case .seasons, .episodes, .related: false
        }
    }

    /// The title's release badge, else (series) whether the episode Play targets has aired.
    var headerBadge: CardBadge? {
        if let title, let badge = ReleaseBadge.forTitle(title) { return badge }
        guard !target.isMovie, let ep = primaryEpisode else { return nil }
        return ReleaseBadge.forEpisode(airDate: ep.airedDate).map { CardBadge(text: $0) }
    }

    var titleText: some View {
        Text(target.name).font(.system(size: 72, weight: .bold)).lineLimit(2)
    }

    var metadataLine: String {
        var parts: [String] = []
        if let y = title?.year ?? target.year { parts.append(String(y)) }
        if let c = title?.certification, !c.isEmpty { parts.append(c) }
        if let r = formatRuntime(title?.runtimeMinutes) { parts.append(r) }
        if !seasons.isEmpty {
            let n = seasons.filter { $0.number > 0 }.count
            parts.append(n == 1 ? "1 Season" : "\(n) Seasons")
        }
        if let g = title?.genres, !g.isEmpty { parts.append(g.prefix(3).joined(separator: ", ")) }
        return parts.joined(separator: "  ·  ")
    }
}
