import SwiftUI

extension DetailsView {
    /// A series' watch state as a menu, like the Live tab's category filter: the current
    /// episode and the whole-show choices close it; each season toggles in place with the
    /// menu left open (checked once every aired episode is watched), so several seasons can be
    /// marked in one visit. Whole-show and whole-season changes carry their scope so
    /// Trakt-style providers record them with their own bulk calls. Only aired episodes are
    /// marked watched; unwatched applies to everything.
    var watchStateMenu: some View {
        Menu {
            let shape = WatchStateSeasons(seasons)
            if let ep = primaryEpisode {
                let watched = isWatched(ep)
                Section("\(ep.code) · \(ep.name)") {
                    Button {
                        markWatched(!watched, [ep], scope: nil)
                    } label: {
                        Label(watched ? "Mark as Unwatched" : "Mark as Watched",
                              systemImage: watched ? "checkmark.circle.badge.xmark" : "checkmark.circle")
                    }
                }
            }
            Section("All Episodes") {
                allEpisodesChoices(shape)
            }
            if !shape.ordered.isEmpty {
                Section("Seasons") {
                    ForEach(shape.ordered) { season in
                        seasonToggle(season, shape)
                    }
                }
            }
        } label: {
            Label { Text("Watch State") } icon: { WatchStateEye(state: seriesWatchState) }
                .labelStyle(.iconOnly)
        }
    }

    @ViewBuilder
    private func allEpisodesChoices(_ shape: WatchStateSeasons) -> some View {
        let latest = shape.excludable
        let rest = shape.ordered.filter { $0.number != latest }
        let aired = shape.aired(shape.ordered)
        Button { markWatched(true, aired, scope: .show) } label: {
            Label("Mark All \(aired.count) as Watched", systemImage: "checkmark.circle")
        }
        .disabled(aired.isEmpty)
        if let latest {
            let restAired = shape.aired(rest)
            Button { markWatched(true, restAired, scope: nil) } label: {
                Label("All Except Season \(latest) as Watched", systemImage: "checkmark.circle")
            }
            .disabled(restAired.isEmpty)
        }
        let all = shape.ordered.flatMap(\.episodes)
        Button { markWatched(false, all, scope: .show) } label: {
            Label("Mark All \(all.count) as Unwatched", systemImage: "xmark.circle")
        }
        .disabled(all.isEmpty)
        if let latest {
            let restAll = rest.flatMap(\.episodes)
            Button { markWatched(false, restAll, scope: nil) } label: {
                Label("All Except Season \(latest) as Unwatched", systemImage: "xmark.circle")
            }
            .disabled(restAll.isEmpty)
        }
    }

    /// Watched (every aired episode) unmarks the whole season; otherwise its aired episodes
    /// are marked, a partly watched season included.
    private func seasonToggle(_ season: Season, _ shape: WatchStateSeasons) -> some View {
        let aired = shape.aired([season])
        let watchedCount = season.episodes.filter(isWatched).count
        let complete = !aired.isEmpty && aired.allSatisfy(isWatched)
        let name = WatchStateSeasons.name(season)
        return Button {
            if complete {
                markWatched(false, season.episodes, scope: WatchStateSeasons.scope(season))
            } else {
                markWatched(true, aired, scope: WatchStateSeasons.scope(season))
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
        .menuActionDismissBehavior(.disabled)
    }

    /// The episodes flip at once (the open menu's checks with them); the page reloads after.
    private func markWatched(_ watched: Bool, _ episodes: [Episode], scope: WatchedScope?) {
        guard !episodes.isEmpty else { return }
        let previous = episodes.map { ($0.id, watchedOverrides[$0.id]) }
        for ep in episodes { watchedOverrides[ep.id] = watched }
        Task {
            do {
                try await APIClient.shared.setWatched(watched, episodes: episodes, of: target, scope: scope)
                watchedError = nil
                await load()
                await titles.seriesWatchStateChanged()
            } catch {
                for (id, value) in previous { watchedOverrides[id] = value }
                titles.show(toast: String(localized: "Failed to update watched state"))
            }
        }
    }
}
