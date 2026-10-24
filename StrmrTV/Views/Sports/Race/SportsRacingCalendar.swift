import SwiftUI

/// Motorsport's Competition Details (Expo `SportsRacingHub`): Race Weekends (every weekend of the
/// board, followed series first, live then upcoming then results, filtered by series, state and
/// favourites) or Championship Standings (`SportsRacingChampionship`: the chosen series' next
/// weekend, then its table). The board reloads every 30 s (60 s on standings).
struct SportsRacingCalendar: View {
    @ObservedObject var hub: SportsHubStore

    @State private var board: SportsRaceBoard?
    @State private var failed = false
    @State private var retries = 0
    @State private var championship = false
    @State private var series: String?
    @State private var status = "all"
    @State private var favorites = false
    @FocusState private var chip: String?

    init(hub: SportsHubStore, initialSeries: String?) {
        self.hub = hub
        _series = State(initialValue: initialSeries)
        _board = State(initialValue: hub.raceBoard)
    }

    private var seriesIDs: [String] { hub.catalog.filter { $0.isUsable && $0.isRacing }.map(\.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SportsBrowseHeading(
                eyebrow: String(localized: "MOTORSPORT / RACE CONTROL"),
                title: championship ? String(localized: "Championship Standings") : String(localized: "Race Weekends"),
                description: championship ? String(localized: "Published season tables. Select a series to explore its championship.")
                    : String(localized: "Session schedules, classifications and circuit guides. Times shown locally."))
            controls
            if championship {
                SportsRacingChampionship(hub: hub, series: series, board: board, failed: failed)
            } else {
                weekends
            }
        }
        .task(id: "\(retries)|\(championship)") {
            while !Task.isCancelled {
                do {
                    board = try await APIClient.shared.sportsRaces()
                    failed = false
                } catch {
                    if error is CancellationError || Task.isCancelled { return }
                    failed = true
                }
                try? await Task.sleep(for: .seconds(championship ? 60 : 30))
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            ForEach([false, true], id: \.self) { value in
                Button(value ? "Championship Standings" : "Race Weekends") { championship = value }
                    .buttonStyle(FilterChipStyle(selected: championship == value))
                    .focused($chip, equals: value ? "championship" : "weekends")
            }
            Menu {
                Picker("Series", selection: $series) {
                    Text("All Racing").tag(String?.none)
                    ForEach(seriesIDs, id: \.self) { Text(hub.leagueName($0)).tag(String?.some($0)) }
                }
            } label: {
                Label("Series: \(series.map(hub.leagueName) ?? String(localized: "All Racing"))", systemImage: "chevron.down")
            }
            .buttonStyle(FilterChipStyle(selected: series != nil))
            .accessibilityIdentifier("sports-racing-series")
            if !championship {
                Button { favorites.toggle() } label: { Label("My Favorites", systemImage: favorites ? "star.fill" : "star") }
                    .buttonStyle(FilterChipStyle(selected: favorites))
            }
        }
        .font(.callout)
        .lineLimit(1)
        .sportsChipRow()
        .defaultFocus($chip, championship ? "championship" : "weekends", priority: .userInitiated)
    }

    @ViewBuilder private var weekends: some View {
        let events = filteredEvents
        HStack(spacing: 18) {
            ForEach([("all", String(localized: "All Weekends")), ("scheduled", String(localized: "Upcoming Races")),
                     ("final", String(localized: "Race Results"))], id: \.0) { id, label in
                Button(label) { status = id }
                    .buttonStyle(FilterChipStyle(selected: status == id))
                    .focused($chip, equals: "status-\(id)")
            }
        }
        .font(.callout)
        .sportsChipRow()
        .defaultFocus($chip, "status-\(status)", priority: .userInitiated)
        Text("\(events.count) weekends in this selection · ESPN / MotoGP").font(.caption).foregroundStyle(.secondary)
        if board == nil && !failed {
            SportsNotice(title: String(localized: "Loading race weekends"), message: String(localized: "Fetching the race calendar."),
                         loading: true)
        }
        if failed || board?.delayed == true {
            let late = (board?.leagues ?? []).filter { $0.stale || $0.unavailable }
                .map { "\(hub.leagueName($0.league)): \($0.unavailable ? String(localized: "unavailable") : String(localized: "updates delayed"))" }
            SportsNotice(title: String(localized: "Racing updates delayed"),
                         message: failed ? String(localized: "Racing updates are unavailable. Any displayed events are from the last successful update.")
                            : late.joined(separator: " · ")) { retries += 1 }
        }
        if board != nil && events.isEmpty && !failed {
            Text(favorites ? "No favorite race weekends match. Follow a series in Customize Sports, or show all racing."
                 : "No race weekends returned for this selection.").foregroundStyle(.secondary).sportsReadout()
        }
        ForEach(events) { SportsRaceWeekendRow(weekend: $0, seriesName: hub.leagueName($0.league)) }
    }

    /// The board's weekends in the selection: followed series first, then live, upcoming (soonest
    /// first), results (latest first).
    private var filteredEvents: [SportsRaceEvent] {
        let ids = Set(seriesIDs), followed = hub.followed, pinned = hub.pinned
        let events = (board?.events ?? []).filter { event in
            ids.contains(event.league) && (series == nil || event.league == series) && (status == "all" || event.status == status)
                && (!favorites || SportsRaceHub.isFollowed(event.league, competitions: followed, pinned: pinned))
        }
        func follows(_ event: SportsRaceEvent) -> Int { followed.contains(SportsRaceHub.followID(event.league)) ? 0 : 1 }
        func state(_ event: SportsRaceEvent) -> Int { event.status == "live" ? 0 : event.status == "scheduled" ? 1 : 2 }
        return events.sorted { a, b in
            if (follows(a), state(a)) != (follows(b), state(b)) { return (follows(a), state(a)) < (follows(b), state(b)) }
            let first = a.start ?? .distantPast, second = b.start ?? .distantPast
            return a.status == "final" ? first > second : first < second
        }
    }
}

/// A browse view's heading (Expo `SportsBrowseHeading`): accent eyebrow, title and a line about it.
struct SportsBrowseHeading: View {
    let eyebrow: String
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SportsEyebrow(text: eyebrow)
            Text(title).font(.system(size: 52, weight: .semibold))
            Text(description).font(.callout).foregroundStyle(.secondary)
        }
    }
}
