#if os(iOS)
import SwiftUI

/// Play / Resume and Start Over, then the Expo phone page's secondary actions as round icon
/// buttons with captions: Choose Source, Versions, Trailer, Watchlist, Lists and the watch
/// state (a toggle for movies, the bulk menu for series).
extension MobileDetailsView {
    var actionsSection: some View {
        VStack(spacing: 18) {
            playArea
            HStack(alignment: .top, spacing: 4) {
                MobileActionItem(caption: String(localized: "Sources")) {
                    Button { model.chooseSource(for: model.activeEpisode) } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .disabled(!target.isMovie && model.activeEpisode == nil)
                    .accessibilityLabel("Choose Source")
                }
                if !model.primaryVersions.isEmpty {
                    MobileActionItem(caption: String(localized: "Versions")) {
                        Button {
                            model.versionsPicker = .init(episode: target.isMovie ? nil : model.activeEpisode)
                        } label: { Image(systemName: "externaldrive") }
                        .accessibilityLabel("Versions")
                    }
                }
                MobileTrailerAction(trailer: model.trailer)
                MobileActionItem(caption: inWatchlist ? String(localized: "Saved") : String(localized: "Watchlist")) {
                    Button { Task { await toggleWatchlist() } } label: {
                        Image(systemName: inWatchlist ? "bookmark.fill" : "bookmark")
                    }
                    .accessibilityLabel(inWatchlist ? "Remove from Watchlist" : "Add to Watchlist")
                }
                MobileActionItem(caption: String(localized: "Lists")) {
                    DetailsListsMenu(target: target).menuStyle(.button)
                }
                watchedAction
            }
            .modifier(MobileSecondaryActionStyle())
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var playArea: some View {
        #if DEBUG
        if let variant = PlayPrototype.selected { playPrototype(variant) } else { primaryRow }
        #else
        primaryRow
        #endif
    }

    private var primaryRow: some View {
        HStack(spacing: 10) {
            let primary = model.primaryTarget
            Button { model.playPrimary() } label: {
                VStack(spacing: 2) {
                    Label(primary?.label ?? String(localized: "Play"), systemImage: "play.fill")
                        .font(.headline)
                    if let start = primary?.start {
                        Text("From \(start.label)").font(.caption2).opacity(0.7)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.white)
            .foregroundStyle(.black)
            .controlSize(.large)
            .overlay(alignment: .bottom) {
                if let primary, primary.start != nil {
                    let fraction = model.resumeFraction(primary.episode)
                    if fraction > 0 {
                        GeometryReader { geo in
                            Capsule().fill(.black.opacity(0.5))
                                .frame(width: geo.size.width * fraction, height: 3)
                        }
                        .frame(height: 3)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 5)
                        .allowsHitTesting(false)
                    }
                }
            }
            .disabled(primary == nil || model.title == nil)

            if let primary, primary.start != nil {
                Button { model.play(primary.episode, from: nil) } label: {
                    Image(systemName: "arrow.counterclockwise").font(.headline).padding(.vertical, 6)
                }
                .modifier(MobileSecondaryActionStyle())
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityLabel("Start Over")
            }
        }
    }

    // MARK: Watchlist

    var inWatchlist: Bool { watchlist.contains(target, server: model.serverInWatchlist) }

    func toggleWatchlist() async {
        guard !watchlistBusy else { return }
        watchlistBusy = true
        defer { watchlistBusy = false }
        do {
            if inWatchlist { try await watchlist.remove(target) } else { try await watchlist.add(target) }
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: Watched

    @ViewBuilder
    private var watchedAction: some View {
        if target.isMovie {
            let watched = model.movieWatched == true
            MobileActionItem(caption: watched ? String(localized: "Watched") : String(localized: "Unwatched")) {
                Button { Task { await toggleMovieWatched() } } label: {
                    WatchStateEye(state: watched ? .complete : .none)
                }
                .accessibilityLabel(watched ? "Mark as Unwatched" : "Mark as Watched")
            }
        } else if !model.seasons.isEmpty {
            MobileActionItem(caption: String(localized: "Watched")) {
                Menu { watchStateItems } label: { WatchStateEye(state: model.seriesWatchState) }
                    .menuStyle(.button)
                    .accessibilityLabel("Watch State")
            }
        }
    }

    func toggleMovieWatched() async {
        guard !watchedBusy else { return }
        watchedBusy = true
        defer { watchedBusy = false }
        actionError = await model.toggleMovieWatched()
    }

    /// The series watch-state menu (the TV page's `watchStateItems`): the selected episode,
    /// the whole show, and each season toggled in place with the menu left open.
    @ViewBuilder
    var watchStateItems: some View {
        let shape = model.watchStateSeasons
        if let ep = model.activeEpisode {
            let watched = model.isWatched(ep)
            Section("\(ep.code) · \(ep.name)") {
                Button { model.markWatched(!watched, [ep], scope: nil, titles: titles) } label: {
                    Label(watched ? "Mark as Unwatched" : "Mark as Watched",
                          systemImage: watched ? "checkmark.circle.badge.xmark" : "checkmark.circle")
                }
            }
        }
        Section("All Episodes") {
            let latest = shape.excludable
            let rest = shape.ordered.filter { $0.number != latest }
            let aired = shape.aired(shape.ordered)
            Button { model.markWatched(true, aired, scope: .show, titles: titles) } label: {
                Label("Mark All \(aired.count) as Watched", systemImage: "checkmark.circle")
            }
            .disabled(aired.isEmpty)
            if let latest {
                let restAired = shape.aired(rest)
                Button { model.markWatched(true, restAired, scope: nil, titles: titles) } label: {
                    Label("All Except Season \(latest) as Watched", systemImage: "checkmark.circle")
                }
                .disabled(restAired.isEmpty)
            }
            let all = shape.ordered.flatMap(\.episodes)
            Button { model.markWatched(false, all, scope: .show, titles: titles) } label: {
                Label("Mark All \(all.count) as Unwatched", systemImage: "xmark.circle")
            }
            .disabled(all.isEmpty)
            if let latest {
                let restAll = rest.flatMap(\.episodes)
                Button { model.markWatched(false, restAll, scope: nil, titles: titles) } label: {
                    Label("All Except Season \(latest) as Unwatched", systemImage: "xmark.circle")
                }
                .disabled(restAll.isEmpty)
            }
        }
        if !shape.ordered.isEmpty {
            Section("Seasons") {
                ForEach(shape.ordered) { season in seasonToggle(season) }
            }
        }
    }

    /// Watched (every aired episode) unmarks the season; otherwise its aired episodes are marked.
    func seasonToggle(_ season: Season, dismissesMenu: Bool = false) -> some View {
        let aired = model.watchStateSeasons.aired([season])
        let watchedCount = season.episodes.filter(model.isWatched).count
        let complete = !aired.isEmpty && aired.allSatisfy(model.isWatched)
        let name = WatchStateSeasons.name(season)
        return Button {
            if complete {
                model.markWatched(false, season.episodes, scope: WatchStateSeasons.scope(season), titles: titles)
            } else {
                model.markWatched(true, aired, scope: WatchStateSeasons.scope(season), titles: titles)
            }
        } label: {
            if complete {
                Label(name, systemImage: "checkmark")
            } else if watchedCount > 0 {
                Text(name)
                Text("\(watchedCount) of \(season.episodes.count) watched")
            } else {
                Text(name)
            }
        }
        .disabled(aired.isEmpty && watchedCount == 0)
        .menuActionDismissBehavior(dismissesMenu ? .automatic : .disabled)
    }
}

/// The page's secondary buttons: white symbols on Liquid Glass (iOS 26), else on a
/// translucent white fill, rather than the accent color's blue.
struct MobileSecondaryActionStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glass).foregroundStyle(.white)
        } else {
            content.buttonStyle(.bordered).tint(.white).foregroundStyle(.white)
        }
    }
}

/// A round icon button with a caption under it, the phone page's secondary action.
struct MobileActionItem<Content: View>: View {
    let caption: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 6) {
            content.font(.body.weight(.semibold))
                // One height for every symbol, so the captions line up.
                .frame(height: 52)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Trailer: full screen in the system player (a spinner while its URL is fetched).
struct MobileTrailerAction: View {
    @ObservedObject var trailer: TrailerController

    var body: some View {
        if trailer.available {
            MobileActionItem(caption: String(localized: "Trailer")) {
                Button { trailer.buttonPressed() } label: {
                    if trailer.preparingFullScreen {
                        ProgressView()
                    } else {
                        Image(systemName: "film")
                    }
                }
                .accessibilityLabel("Play Trailer")
            }
            .fullScreenCover(item: $trailer.fullScreen) { item in
                TrailerPlayerView(url: item.url) { trailer.fullScreen = nil }
                    .ignoresSafeArea()
            }
        }
    }
}
#endif
