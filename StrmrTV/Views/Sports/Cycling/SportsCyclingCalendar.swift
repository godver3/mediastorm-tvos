import SwiftUI

/// Cycling's Competition Details (Expo `SportsCyclingHub`): the organizers' race calendar, current
/// races first, then upcoming ones and recent history, narrowed by dates, category, format and
/// favourites; 24 at a time. A race opens its page. Reloads every 5 min.
struct SportsCyclingCalendar: View {
    @ObservedObject var hub: SportsHubStore

    @State private var feed: SportsCyclingFeed?
    @State private var failed = false
    @State private var retries = 0
    @State private var dates = "all"
    @State private var category = "all"
    @State private var format = "all"
    @State private var favorites = false
    @State private var shown = 24

    private static let datesChoices = [("all", String(localized: "All Dates")), ("current", String(localized: "Current Race Dates")),
                                       ("upcoming", String(localized: "Upcoming Races")), ("past", String(localized: "Past Race Dates"))]
    private static let categoryChoices = [("all", String(localized: "All Road Cycling")), ("men", String(localized: "Men's Races")),
                                          ("women", String(localized: "Women's Races"))]
    private static let formatChoices = [("all", String(localized: "All Formats")), ("stage-race", String(localized: "Stage Races")),
                                        ("one-day", String(localized: "One-Day Races"))]

    var body: some View {
        let today = SportsCycling.today()
        let races = filtered(today)
        VStack(alignment: .leading, spacing: 24) {
            SportsBrowseHeading(eyebrow: String(localized: "ROAD CYCLING / STAGE ATLAS"), title: String(localized: "The Race Calendar"),
                                description: String(localized: "Grand Tours, stage races and one-day classics. Published results, routes and standings."))
            HStack(spacing: 18) {
                menu(String(localized: "Race Dates"), Self.datesChoices, $dates)
                menu(String(localized: "Category"), Self.categoryChoices, $category)
                menu(String(localized: "Format"), Self.formatChoices, $format)
                Button { favorites.toggle() } label: { Label("My Favorites", systemImage: favorites ? "star.fill" : "star") }
                    .buttonStyle(FilterChipStyle(selected: favorites))
            }
            .font(.callout)
            .lineLimit(1)
            .sportsChipRow()
            .accessibilityIdentifier("sports-cycling-calendar-filters")
            Text("Current dates first, then upcoming races and recent history. Dates do not indicate live coverage.")
                .font(.caption).foregroundStyle(.secondary)
            notices
            ForEach(races.prefix(shown)) { SportsCyclingCalendarRow(race: $0, today: today) }
            if races.count > shown {
                Button(String(localized: "Show More Races (\(min(shown, races.count)) of \(races.count))")) { shown += 24 }
            }
            if let feed, !feed.races.isEmpty {
                if races.isEmpty {
                    Text(favorites ? "No favorite races match. Follow a race in Customize Sports, or show all cycling."
                         : "No races returned for this selection.").foregroundStyle(.secondary).sportsReadout()
                }
                Text("Organizer schedules and published results · Grand Tours, stage races and spring classics. Live timing is not connected.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .onAppear { if feed == nil { feed = hub.cyclingFeed } }
        .task(id: retries) {
            while !Task.isCancelled {
                do {
                    feed = try await APIClient.shared.sportsCycling()
                    failed = false
                } catch {
                    if error is CancellationError || Task.isCancelled { return }
                    failed = true
                }
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    private func filtered(_ today: String) -> [SportsCyclingRace] {
        let followed = hub.followed, pinned = hub.pinned
        let races = (feed?.races ?? []).filter { race in
            (!favorites || SportsCycling.isFollowed(race, competitions: followed, pinned: pinned))
                && (format == "all" || race.format == format) && (category == "all" || race.category == category)
                && (dates == "all" || "\(SportsCycling.period(race, today: today))" == dates)
        }
        // Followed races first among equals (Expo).
        return races.enumerated().sorted { a, b in
            if SportsCycling.calendarOrder(a.element, b.element, today: today) { return true }
            if SportsCycling.calendarOrder(b.element, a.element, today: today) { return false }
            let first = followed.contains(a.element.followID) ? 0 : 1, second = followed.contains(b.element.followID) ? 0 : 1
            return (first, a.offset) < (second, b.offset)
        }.map(\.element)
    }

    @ViewBuilder private var notices: some View {
        if failed || feed?.delayed == true {
            SportsNotice(title: String(localized: "Cycling updates delayed"),
                         message: String(localized: "Some cycling updates are unavailable. Displayed races may be from an earlier update.")) {
                retries += 1
            }
        }
        if feed == nil && !failed {
            SportsNotice(title: String(localized: "Loading cycling coverage"),
                         message: String(localized: "Fetching the organizers' calendars."), loading: true)
        }
        if feed?.state == "unsupported" || feed?.state == "pending" {
            SportsNotice(title: String(localized: "Cycling results are not connected yet"),
                         message: String(localized: "Race schedules, stage results and overall standings will appear here when coverage is connected."))
        }
        let late = (feed?.coverage ?? []).filter { $0.state != "available" }
            .map { "\($0.name): \($0.state == "stale" ? String(localized: "updates delayed") : String(localized: "unavailable"))" }
        if !late.isEmpty { Text(late.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
    }

    private func menu(_ title: String, _ choices: [(String, String)], _ value: Binding<String>) -> some View {
        Menu {
            Picker(title, selection: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; shown = 24 })) {
                ForEach(choices, id: \.0) { Text($0.1).tag($0.0) }
            }
        } label: {
            Label(choices.first { $0.0 == value.wrappedValue }?.1 ?? title, systemImage: "chevron.down")
        }
        .buttonStyle(FilterChipStyle(selected: value.wrappedValue != "all"))
    }
}
