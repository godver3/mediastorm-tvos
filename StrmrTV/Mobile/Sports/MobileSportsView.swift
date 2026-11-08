#if os(iOS)
import SwiftUI

/// The Sports section on a phone, a port of the Expo mobile hub (`app/(drawer)/sports.tsx` with
/// `SportsHubTV`) on the TV's `SportsHubStore`: a segmented All / Live / Upcoming / Results
/// filter, chips for the day, sport, competition, Following and My Teams, then a section of
/// cards per state (Live Now, Upcoming, Results, Schedule Updates) with followed competitions and
/// pinned sports first. Search narrows the cards by team, competition or event; the toolbar
/// holds Hide Scores and Customize. A game opens its page (`MobileSportsGameView`), a race
/// session its weekend's (`MobileSportsRaceView`), a cycling stage its race's
/// (`MobileSportsCyclingView`).
struct MobileSportsView: View {
    @StateObject private var store = SportsHubStore()
    @ObservedObject private var spoilers = SportsSpoilers.shared
    @State private var query = ""
    @State private var customizing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MobileSportsHubControls(store: store)
                if store.filtered { MobileSportsFilterSummary(store: store, spoilers: spoilers.hidden) }
                notices
                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Sports")
        .searchable(text: $query, prompt: "Teams, competitions and events")
        .refreshable { await store.retry() }
        .toolbar { toolbar }
        .sheet(isPresented: $customizing) { MobileSportsPreferencesSheet(hub: store) }
        .task { await store.loadPreferences() }
        .task {
            await store.load()
            await store.poll()
        }
        .task(id: "\(store.racingEnabled)|\(store.raceRetries)") {
            if store.racingEnabled { await store.pollRaces() }
        }
        .task(id: "\(store.cyclingEnabled)|\(store.raceRetries)") {
            if store.cyclingEnabled { await store.pollCycling() }
        }
        .task(id: store.recordLeagues) { await store.loadRecords() }
        .mobileSportsDestinations(hub: store)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Toggle(isOn: $spoilers.hidden) { Label("Hide Scores", systemImage: "eye.slash") }
                Button { customizing = true } label: { Label("Customize Sports", systemImage: "slider.horizontal.3") }
                if let updated = store.updatedAt {
                    Section { Text(MobileSportsFormat.freshness(updated)) }
                }
            } label: {
                Label("Options", systemImage: spoilers.hidden ? "eye.slash.circle" : "ellipsis.circle")
            }
            .accessibilityIdentifier("sports-options")
        }
    }

    /// The day's sections, narrowed by the search.
    private var sections: [SportsSection] {
        let words = query.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return store.sections }
        return store.sections.compactMap { section in
            let items = section.items.filter { MobileSportsSearch.matches($0, query: words, league: store.leagueName) }
            return items.isEmpty ? nil : SportsSection(kind: section.kind, items: items)
        }
    }

    @ViewBuilder private var notices: some View {
        let delayed = [store.error.map { String(localized: "Scores may be delayed: \($0)") },
                       store.racingDelayed ? String(localized: "Racing updates delayed or unavailable") : nil,
                       store.cyclingDelayed ? String(localized: "Cycling updates delayed or unavailable") : nil].compactMap { $0 }
        if !delayed.isEmpty, !store.sections.isEmpty {
            Label(delayed.joined(separator: " · "), systemImage: "exclamationmark.triangle")
                .font(.footnote).foregroundStyle(SportsStatusPill.amber)
        }
    }

    @ViewBuilder private var content: some View {
        let sections = sections
        if (store.loading && store.games.isEmpty || store.racesPending || store.cyclingPending) && sections.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
        } else if let error = store.error, store.sections.isEmpty {
            ContentUnavailableView {
                Label("Sports Unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { Task { await store.retry() } }.buttonStyle(.bordered)
            }
            .padding(.top, 40)
        } else if sections.isEmpty {
            empty
        } else {
            ForEach(sections) { section in
                MobileSportsHubSection(section: section, store: store, spoilers: spoilers.hidden)
            }
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label(query.isEmpty ? "No Events" : "No Matching Events", systemImage: "sportscourt")
        } description: {
            Text(query.isEmpty ? MobileSportsFormat.emptyText(store) : String(localized: "Try another team, competition or event."))
        } actions: {
            if store.filtered {
                Button("Clear Filters") { store.clearFilters() }.buttonStyle(.bordered)
            } else if store.followingOnly || store.myTeamsOnly {
                Button("Show All Events") {
                    store.followingOnly = false
                    store.myTeamsOnly = false
                }
                .buttonStyle(.bordered)
            }
            if store.myTeamsOnly, store.followedTeams.isEmpty {
                Button("Customize Sports") { customizing = true }
            }
        }
        .padding(.top, 40)
    }
}

/// A state's section of the hub: its title and count over a grid of cards, one column on a
/// phone held upright and more as the width allows.
struct MobileSportsHubSection: View {
    let section: SportsSection
    @ObservedObject var store: SportsHubStore
    let spoilers: Bool

    private static let columns = [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if section.kind == .live { Circle().fill(SportsStatusPill.live).frame(width: 8, height: 8) }
                Text(section.title).font(.title3.weight(.semibold))
                Text("\(section.items.count)").font(.subheadline).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 12) {
                ForEach(section.items) { item in
                    MobileSportsHubCard(item: item, store: store, spoilers: spoilers)
                }
            }
        }
        .padding(.top, 8)
        .task(id: section.items.map(\.id)) {
            SportsTeamLogo.prefetch(section.items.compactMap { if case let .game(game) = $0 { game } else { nil } })
        }
    }
}

/// The search over the hub's cards: a team's name or abbreviation, the event's title, its
/// competition.
enum MobileSportsSearch {
    static func matches(_ item: SportsHubItem, query: String, league: (String) -> String) -> Bool {
        let fields: [String] = switch item {
        case let .game(game):
            [game.displayTitle, game.homeTeam.name, game.awayTeam.name, game.homeTeam.abbreviation ?? "",
             game.awayTeam.abbreviation ?? "", league(game.league)]
        case let .race(listing):
            [listing.weekend.title, listing.session.sessionType ?? "", league(listing.session.league)]
        case let .cycling(listing):
            [listing.race.name, listing.stage?.name ?? "", String(localized: "Cycling")]
        }
        return fields.contains { $0.localizedStandardContains(query) }
    }
}

/// The hub's words for its states.
enum MobileSportsFormat {
    static func freshness(_ updated: Date, now: Date = Date()) -> String {
        let minutes = Int(now.timeIntervalSince(updated) / 60)
        return minutes < 1 ? String(localized: "Updated just now") : String(localized: "Updated \(minutes) min ago")
    }

    /// What an empty hub says (the TV hub's lines).
    @MainActor static func emptyText(_ store: SportsHubStore) -> String {
        let day = store.day.label.lowercased()
        if store.myTeamsOnly, store.followedTeams.isEmpty {
            return String(localized: "Follow a team from its game page or Customize to see only its games.")
        }
        if store.filtered { return String(localized: "Nothing in this selection \(day).") }
        if store.followingOnly { return String(localized: "Nothing from the competitions you follow \(day).") }
        return switch store.filter {
        case .live: String(localized: "Nothing is live right now.")
        case .upcoming: String(localized: "Nothing else is scheduled \(day).")
        case .results: String(localized: "No results yet \(day).")
        case .all: String(localized: "No events \(day).")
        }
    }
}
#endif
