import SwiftUI

/// The Sports tab, a native take on the Expo TV hub: filters, day, sport, league and options
/// across the top (`SportsHubControls`, with `SportsFilterSummary` under them while a sport or
/// league is chosen), then a row of events per state (Live Now, Upcoming, Results, Schedule
/// Updates), followed competitions and pinned sports first in each. A game opens its page
/// (`SportsGameView`), a race session its weekend's (`SportsRaceView`) and a cycling stage its
/// race's (`SportsCyclingView`), where they are watched.
struct SportsHubView: View {
    @StateObject private var store = SportsHubStore()
    @ObservedObject private var spoilers = SportsSpoilers.shared
    @FocusState private var focus: String?

    /// Where the fade under the tab pill starts and how tall it is (screen points).
    private static let fadeStart: CGFloat = 112
    private static let fade: CGFloat = 24
    private static let top = "sports-hub-top"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 44) {
                    header.id(Self.top)
                    SportsHubControls(store: store, spoilers: spoilers, focus: $focus)
                    if store.filtered {
                        SportsFilterSummary(store: store, spoilers: spoilers.hidden, focus: $focus).padding(.top, -24)
                    }
                    content
                }
                .padding(.horizontal, CardGridLayout.inset)
                .padding(.bottom, 80)
            }
            // Back up in the controls, the page goes all the way to its top. Focus alone scrolls
            // only as far as the chip, leaving the title out of view and, with the top bar (shown
            // only while the page is at its top), the menu too.
            .onChange(of: focus) { _, new in
                guard new != nil else { return }
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(Self.top, anchor: .top) }
            }
        }
        .scrollClipDisabled()
        // Rows scrolled up fade out under the menu's tab pill instead of running beneath it.
        .mask(alignment: .top) {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: Self.fade)
                Color.black
            }
            .padding(.top, Self.fadeStart)
            .ignoresSafeArea()
        }
        // No default focus here: coming back from the side menu returns to the card it left (a
        // default would send it to the chips every time); the first chip is the top-left anyway.
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
        .navigationDestination(for: SportsGameRef.self) { SportsGameView(ref: $0, leagues: store.leagues).pinsSideMenu() }
        .navigationDestination(for: SportsRaceRef.self) { ref in
            SportsRaceView(ref: ref, board: store.raceBoard, leagueName: store.leagueName).pinsSideMenu()
        }
        .navigationDestination(for: SportsCyclingRef.self) { SportsCyclingView(ref: $0, hub: store).pinsSideMenu() }
        .navigationDestination(for: SportsCompetitionRoute.self) { SportsCompetitionView(route: $0, hub: store).pinsSideMenu() }
        .navigationDestination(for: SportsPreferencesRoute.self) { _ in
            SportsPreferencesView(leagues: store.usableLeagues) { store.preferences = $0 }.pinsSideMenu()
        }
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            Text("Sports").font(.system(size: 50, weight: .medium))
            Spacer()
            if let updated = store.updatedAt {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(Self.freshness(updated, now: context.date)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        let sections = store.sections
        if (store.loading && store.games.isEmpty || store.racesPending || store.cyclingPending) && sections.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 120)
        } else if let error = store.error, sections.isEmpty {
            // Races can still show when the scoreboard fails; the "delayed" line says so.
            notice(error, action: String(localized: "Try Again")) { Task { await store.retry() } }
        } else if sections.isEmpty {
            let action = store.filtered ? String(localized: "Clear Filters")
                : store.followingOnly ? String(localized: "Show All Events") : nil
            notice(emptyText, action: action) {
                if store.filtered { store.clearFilters() } else { store.followingOnly = false }
            }
        } else {
            if let error = store.error {
                Text("Scores may be delayed: \(error)").font(.caption).foregroundStyle(SportsStatusPill.amber)
            }
            let delayed = [store.racingDelayed ? String(localized: "Racing updates delayed or unavailable") : nil,
                           store.cyclingDelayed ? String(localized: "Cycling updates delayed or unavailable") : nil].compactMap { $0 }
            if !delayed.isEmpty {
                Text(delayed.joined(separator: " · ")).font(.caption).foregroundStyle(SportsStatusPill.amber)
            }
            ForEach(sections) { section in
                row(section)
            }
        }
    }

    private var emptyText: String {
        if store.filtered { return String(localized: "Nothing in this selection \(store.day.label.lowercased()).") }
        if store.followingOnly { return String(localized: "Nothing from the competitions you follow \(store.day.label.lowercased()).") }
        return switch store.filter {
        case .live: String(localized: "Nothing is live right now.")
        case .upcoming: String(localized: "Nothing else is scheduled \(store.day.label.lowercased()).")
        case .results: String(localized: "No results yet \(store.day.label.lowercased()).")
        case .all: String(localized: "No events \(store.day.label.lowercased()).")
        }
    }

    private func row(_ section: SportsSection) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                if section.kind == .live { Circle().fill(SportsStatusPill.live).frame(width: 12, height: 12) }
                Text(section.title).font(.title3.weight(.semibold))
                Text("\(section.items.count)").font(.callout).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                LazyHStack(spacing: CardGridLayout.spacing) {
                    ForEach(section.items) { item in
                        switch item {
                        case let .game(game):
                            SportsGameCard(game: game, leagueName: store.leagueName(game.league), kind: store.kind(game),
                                           spoilers: spoilers.hidden, stale: store.staleLeagues.contains(game.league))
                        case let .race(listing):
                            SportsRaceCard(listing: listing, leagueName: store.leagueName(listing.session.league),
                                           spoilers: spoilers.hidden)
                        case let .cycling(listing):
                            SportsCyclingCard(listing: listing, spoilers: spoilers.hidden)
                        }
                    }
                }
                .padding(.vertical, 20)
            }
            .scrollClipDisabled()
            .focusSection()
        }
    }

    private func notice(_ text: String, action: String?, perform: @escaping () -> Void) -> some View {
        VStack(spacing: 28) {
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let action { Button(action, action: perform) }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    private static func freshness(_ updated: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(updated) / 60)
        return minutes < 1 ? String(localized: "Updated just now") : String(localized: "Updated \(minutes) min ago")
    }
}

/// Value pushed to open the Sports preferences.
struct SportsPreferencesRoute: Hashable {}
