import SwiftUI

/// A series' bulk watched / unwatched choices: the Expo app's bulk-watch modal as two native
/// dialogs. The first offers the current episode, all episodes (or all but the most recent
/// season) and By Season…, which opens the second, one choice per season by its state.
/// Whole-show and whole-season changes carry their scope so Trakt-style providers record
/// them with their own bulk calls. Only aired episodes are marked watched; unwatched applies
/// to everything. Each dialog closes on its choice; the store's toast reports the result.
struct WatchStateRequest: Identifiable {
    let series: DetailsTarget
    let seasons: [Season]
    /// The episode the details page plays next.
    var currentEpisode: Episode?

    var id: String { series.titleID }
}

extension View {
    /// `onChanged` runs after every successful change, so the page can reload.
    func watchStateDialogs(_ request: Binding<WatchStateRequest?>, isWatched: @escaping (Episode) -> Bool,
                           onChanged: @escaping () async -> Void) -> some View {
        modifier(WatchStateDialogs(request: request, isWatched: isWatched, onChanged: onChanged))
    }
}

private struct WatchStateDialogs: ViewModifier {
    @EnvironmentObject private var titles: TitleStateStore
    @Binding var request: WatchStateRequest?
    let isWatched: (Episode) -> Bool
    let onChanged: () async -> Void
    /// By Season… opens this once the first dialog is gone.
    @State private var bySeason: WatchStateRequest?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(String(localized: "Mark as Watched"),
                                isPresented: Binding(get: { request != nil }, set: { if !$0 { request = nil } }),
                                titleVisibility: .visible, presenting: request) { request in
                mainChoices(request)
            } message: { request in
                Text(request.series.name)
            }
            .confirmationDialog(String(localized: "Mark Season"),
                                isPresented: Binding(get: { bySeason != nil }, set: { if !$0 { bySeason = nil } }),
                                titleVisibility: .visible, presenting: bySeason) { request in
                seasonChoices(request)
            } message: { request in
                Text(request.series.name)
            }
    }

    @ViewBuilder
    private func mainChoices(_ request: WatchStateRequest) -> some View {
        let shape = WatchStateSeasons(request.seasons)
        if let ep = request.currentEpisode {
            let watched = isWatched(ep)
            Button(watched ? "Mark \(ep.code) as Unwatched" : "Mark \(ep.code) as Watched") {
                apply(!watched, [ep], of: request, scope: nil,
                      done: watched ? String(localized: "Marked \(ep.code) as unwatched")
                          : String(localized: "Marked \(ep.code) as watched"))
            }
        }
        let aired = shape.aired(shape.ordered)
        if !aired.isEmpty {
            Button("Mark All \(aired.count) Episodes as Watched") {
                apply(true, aired, of: request, scope: .show, done: String(localized: "Marked all episodes as watched"))
            }
        }
        if let latest = shape.excludable {
            let rest = shape.ordered.filter { $0.number != latest }
            let restAired = shape.aired(rest)
            if !restAired.isEmpty {
                Button("Mark All Except Season \(latest) as Watched") {
                    apply(true, restAired, of: request, scope: nil,
                          done: String(localized: "Marked all but Season \(latest) as watched"))
                }
            }
        }
        let all = shape.ordered.flatMap(\.episodes)
        if !all.isEmpty {
            Button("Mark All \(all.count) Episodes as Unwatched") {
                apply(false, all, of: request, scope: .show, done: String(localized: "Marked all episodes as unwatched"))
            }
        }
        if let latest = shape.excludable {
            let rest = shape.ordered.filter { $0.number != latest }.flatMap(\.episodes)
            if !rest.isEmpty {
                Button("Mark All Except Season \(latest) as Unwatched") {
                    apply(false, rest, of: request, scope: nil,
                          done: String(localized: "Marked all but Season \(latest) as unwatched"))
                }
            }
        }
        if !shape.ordered.isEmpty {
            Button("By Season…") { openBySeason(request) }
        }
        Button("Cancel", role: .cancel) {}
    }

    /// Each season once, by its state: Mark as Watched until every aired episode is, then
    /// Mark as Unwatched; a partly watched season offers both.
    @ViewBuilder
    private func seasonChoices(_ request: WatchStateRequest) -> some View {
        let shape = WatchStateSeasons(request.seasons)
        ForEach(shape.ordered) { season in
            let name = WatchStateSeasons.name(season)
            let toWatch = shape.aired([season])
            let watchedCount = season.episodes.filter(isWatched).count
            let scope = WatchStateSeasons.scope(season)
            if toWatch.contains(where: { !isWatched($0) }) {
                Button("Mark \(name) as Watched") {
                    apply(true, toWatch, of: request, scope: scope, done: String(localized: "Marked \(name) as watched"))
                }
            }
            if watchedCount > 0 {
                Button("Mark \(name) as Unwatched") {
                    apply(false, season.episodes, of: request, scope: scope,
                          done: String(localized: "Marked \(name) as unwatched"))
                }
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    /// The first dialog has to be off screen before the second can present.
    private func openBySeason(_ request: WatchStateRequest) {
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            bySeason = request
        }
    }

    private func apply(_ watched: Bool, _ episodes: [Episode], of request: WatchStateRequest,
                       scope: WatchedScope?, done: String) {
        guard !episodes.isEmpty else { return }
        let titles = titles
        Task {
            do {
                try await APIClient.shared.setWatched(watched, episodes: episodes, of: request.series, scope: scope)
                titles.log.notice("marked \(episodes.count) of \(request.series.titleID) \(watched ? "watched" : "unwatched")")
                titles.show(toast: done)
                await onChanged()
            } catch {
                titles.log.error("bulk mark \(request.series.titleID) failed: \(error.localizedDescription)")
                titles.show(toast: String(localized: "Failed to update watched state"))
            }
        }
    }
}

/// A series' seasons in order, with the aired episodes per season parsed once (parsing every
/// air date per render is slow on long series).
struct WatchStateSeasons {
    let ordered: [Season]
    private let airedBySeason: [String: [Episode]]

    init(_ seasons: [Season]) {
        ordered = seasons.sorted { $0.number < $1.number }
        airedBySeason = Dictionary(seasons.map { season in
            (season.id, season.episodes.filter { ReleaseBadge.forEpisode(airDate: $0.airedDate) == nil })
        }, uniquingKeysWith: { a, _ in a })
    }

    /// The most recent regular season, which the "All Except" choices leave out (even partly
    /// aired); nil unless there is more than one regular season.
    var excludable: Int? {
        let regular = ordered.map(\.number).filter { $0 > 0 }
        return regular.count > 1 ? regular.max() : nil
    }

    func aired(_ seasons: [Season]) -> [Episode] { seasons.flatMap { airedBySeason[$0.id] ?? [] } }

    /// "Specials" or "Season N".
    static func name(_ season: Season) -> String {
        season.number == 0 ? String(localized: "Specials") : String(localized: "Season \(season.number)")
    }

    /// Specials are not a season to Trakt-style providers; they are sent unscoped.
    static func scope(_ season: Season) -> WatchedScope? { season.number > 0 ? .season : nil }
}
