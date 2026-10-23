import SwiftUI

/// Bulk watched / unwatched for a series, laid out like the Expo app's bulk-watch modal:
/// all episodes (optionally leaving out the latest season), the episode the details page
/// is on, and each season. Whole-show and whole-season changes carry their scope so
/// Trakt-style providers record them with their own bulk calls.
struct WatchStateView: View {
    let series: DetailsTarget
    let seasons: [Season]
    /// The episode the details page plays next.
    let currentEpisode: Episode?
    let isWatched: (Episode) -> Bool
    /// Runs after every successful change, so the details page can reload.
    let onChanged: () async -> Void

    /// Aired episodes per season ID, computed once: parsing every air date per render is slow
    /// on long series.
    private let airedBySeason: [String: [Episode]]

    init(series: DetailsTarget, seasons: [Season], currentEpisode: Episode?,
         isWatched: @escaping (Episode) -> Bool, onChanged: @escaping () async -> Void) {
        self.series = series
        self.seasons = seasons
        self.currentEpisode = currentEpisode
        self.isWatched = isWatched
        self.onChanged = onChanged
        airedBySeason = Dictionary(seasons.map { ($0.id, Self.aired($0.episodes)) }, uniquingKeysWith: { a, _ in a })
    }

    @Environment(\.dismiss) private var dismiss
    @State private var excludeLatestSeason = false
    /// Row key → in flight / just succeeded, for the per-season feedback.
    @State private var busy: Set<String> = []
    @State private var done: Set<String> = []
    @State private var error: String?

    private var ordered: [Season] { seasons.sorted { $0.number < $1.number } }

    /// The most recent regular season, which "exclude" leaves out (even partly aired).
    private var latestSeason: Int? { seasons.map(\.number).filter { $0 > 0 }.max() }

    private var includedSeasons: [Season] {
        ordered.filter { !excludeLatestSeason || $0.number != latestSeason }
    }

    private var allEpisodes: [Episode] { includedSeasons.flatMap(\.episodes) }

    private var allAired: [Episode] { includedSeasons.flatMap { airedBySeason[$0.id] ?? [] } }

    /// Only aired episodes are marked watched; unwatched applies to everything.
    private static func aired(_ episodes: [Episode]) -> [Episode] {
        episodes.filter { ReleaseBadge.forEpisode(airDate: $0.airedDate) == nil }
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mark Episodes as Watched").font(.title2.weight(.semibold))
                    Text(series.name).font(.callout).foregroundStyle(.secondary)
                    if let error { Text(error).font(.callout).foregroundStyle(.red) }
                }
                .padding(.bottom, 24)

                sectionTitle("All Episodes")
                if latestSeason != nil, seasons.filter({ $0.number > 0 }).count > 1 {
                    row(key: "exclude", systemImage: excludeLatestSeason ? "checkmark.square.fill" : "square",
                        title: String(localized: "Exclude most recent season")) {
                        excludeLatestSeason.toggle()
                    }
                }
                let watchAll = allAired
                row(key: "all-watched", systemImage: "checkmark.circle",
                    title: String(localized: "Mark all \(watchAll.count) episodes as watched"), disabled: watchAll.isEmpty) {
                    await apply(true, watchAll, scope: excludeLatestSeason ? nil : .show, key: "all-watched", close: true)
                }
                row(key: "all-unwatched", systemImage: "xmark.circle",
                    title: String(localized: "Mark all \(allEpisodes.count) episodes as unwatched"), disabled: allEpisodes.isEmpty) {
                    await apply(false, allEpisodes, scope: excludeLatestSeason ? nil : .show, key: "all-unwatched", close: true)
                }

                if let ep = currentEpisode {
                    sectionTitle("Current Episode · \(ep.code) · \(ep.name)")
                    let watched = isWatched(ep)
                    row(key: "current-watched", systemImage: "checkmark",
                        title: watched ? String(localized: "Already watched") : String(localized: "Mark as watched")) {
                        await apply(true, [ep], scope: nil, key: "current-watched", close: true)
                    }
                    row(key: "current-unwatched", systemImage: "xmark",
                        title: watched ? String(localized: "Mark as unwatched") : String(localized: "Already unwatched")) {
                        await apply(false, [ep], scope: nil, key: "current-unwatched", close: true)
                    }
                }

                if !ordered.isEmpty {
                    sectionTitle("By Season")
                    ForEach(ordered) { season in
                        Text(season.number == 0 ? String(localized: "Specials") : season.name)
                            .font(.headline)
                            .padding(.top, 12)
                        seasonRows(season)
                    }
                }

                row(key: "close", systemImage: "chevron.backward", title: String(localized: "Close")) { dismiss() }
                    .padding(.top, 30)
            }
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        }
        .scrollClipDisabled()
        // Near-opaque, edge to edge: the details page underneath only distracts.
        .background { Color.black.opacity(0.94).ignoresSafeArea() }
    }

    @ViewBuilder
    private func seasonRows(_ season: Season) -> some View {
        let watchKey = "\(season.id)-watched", unwatchKey = "\(season.id)-unwatched"
        let toWatch = airedBySeason[season.id] ?? []
        // Specials are not a season to Trakt-style providers; send them unscoped.
        let scope: WatchedScope? = season.number > 0 ? .season : nil
        row(key: watchKey, systemImage: done.contains(watchKey) ? "checkmark.circle.fill" : "checkmark",
            title: done.contains(watchKey) ? String(localized: "Marked as watched")
                : toWatch.count == 1 ? String(localized: "Mark 1 episode as watched")
                : String(localized: "Mark \(toWatch.count) episodes as watched"),
            disabled: toWatch.isEmpty) {
            await apply(true, toWatch, scope: scope, key: watchKey, close: false)
        }
        row(key: unwatchKey, systemImage: done.contains(unwatchKey) ? "checkmark.circle.fill" : "xmark",
            title: done.contains(unwatchKey) ? String(localized: "Marked as unwatched")
                : season.episodes.count == 1 ? String(localized: "Mark 1 episode as unwatched")
                : String(localized: "Mark \(season.episodes.count) episodes as unwatched"),
            disabled: season.episodes.isEmpty) {
            await apply(false, season.episodes, scope: scope, key: unwatchKey, close: false)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.callout.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 24)
    }

    /// One focusable row. Repeat presses while its change is in flight are ignored rather
    /// than disabling the row, which would drop focus.
    private func row(key: String, systemImage: String, title: String, disabled: Bool = false,
                     action: @escaping () async -> Void) -> some View {
        Button {
            guard !busy.contains(key) else { return }
            Task { await action() }
        } label: {
            HStack(spacing: 20) {
                Image(systemName: systemImage).frame(width: 40)
                Text(title)
                Spacer()
                if busy.contains(key) { ProgressView() }
            }
            .font(.callout)
        }
        .buttonStyle(WatchStateRowStyle())
        .disabled(disabled)
        .accessibilityIdentifier("WatchState-\(key)")
    }

    private func apply(_ watched: Bool, _ episodes: [Episode], scope: WatchedScope?, key: String, close: Bool) async {
        guard !episodes.isEmpty else { return }
        busy.insert(key)
        defer { busy.remove(key) }
        do {
            try await APIClient.shared.setWatched(watched, episodes: episodes, of: series, scope: scope)
            error = nil
            await onChanged()
            if close { return dismiss() }
            done.insert(key)
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                done.remove(key)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct WatchStateRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(isFocused ? Color.black : Color.white.opacity(isEnabled ? 1 : 0.4))
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isFocused ? Color.white : Color.white.opacity(0.08))
                )
                .scaleEffect(configuration.isPressed ? 0.99 : isFocused ? 1.02 : 1)
                .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 18, y: 10)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}
