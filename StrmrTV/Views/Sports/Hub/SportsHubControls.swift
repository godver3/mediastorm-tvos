import SwiftUI

/// The hub's controls (Expo `SportsHubTV`'s TV rail and Filters panel, as native chips): All /
/// Live / Upcoming / Results, the day, the Sport and League menus (pinned sports and followed
/// competitions first), Following, Hide Scores and Customize. The row scrolls sideways when it
/// outgrows the screen.
struct SportsHubControls: View {
    @ObservedObject var store: SportsHubStore
    @ObservedObject var spoilers: SportsSpoilers
    let focus: FocusState<String?>.Binding

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                ForEach(SportsFilter.allCases) { filter in
                    Button(filter.label) { store.filter = filter }
                        .buttonStyle(FilterChipStyle(selected: store.filter == filter))
                        .focused(focus, equals: "filter-\(filter.rawValue)")
                }
                if store.dated {
                    Menu {
                        Picker("Day", selection: $store.day) {
                            ForEach(SportsDay.allCases) { Text($0.label).tag($0) }
                        }
                    } label: {
                        Label(store.day.label, systemImage: "calendar")
                    }
                    .buttonStyle(FilterChipStyle(selected: store.day != .today))
                    .accessibilityIdentifier("sports-day")
                }
                sportMenu
                leagueMenu
                Divider().frame(height: 40)
                Button { store.followingOnly.toggle() } label: {
                    Label("Following", systemImage: store.followingOnly ? "star.fill" : "star")
                }
                .buttonStyle(FilterChipStyle(selected: store.followingOnly))
                Button { spoilers.hidden.toggle() } label: {
                    Label("Hide Scores", systemImage: spoilers.hidden ? "eye.slash.fill" : "eye")
                }
                .buttonStyle(FilterChipStyle(selected: spoilers.hidden))
                .accessibilityIdentifier("sports-hide-scores")
                NavigationLink(value: SportsPreferencesRoute()) {
                    Image(systemName: "slider.horizontal.3").accessibilityLabel("Customize Sports")
                }
                .buttonStyle(FilterChipStyle(selected: false))
            }
            .font(.callout)
            .lineLimit(1)
            .fixedSize()
            .padding(.vertical, 12)
        }
        .scrollClipDisabled()
        .focusSection()
    }

    /// Sport: All Sports, then the sports with a league turned on (pinned first).
    private var sportMenu: some View {
        Menu {
            Picker("Sport", selection: Binding(get: { store.sport }, set: { store.chooseSport($0) })) {
                Text(SportsHubFilters.sportLabel(SportsHubFilters.all)).tag(SportsHubFilters.all)
                ForEach(store.sportOptions) { Text($0.label).tag($0.id) }
            }
        } label: {
            Label(SportsHubFilters.sportLabel(store.sport), systemImage: "chevron.down")
        }
        .buttonStyle(FilterChipStyle(selected: store.sport != SportsHubFilters.all))
        .accessibilityIdentifier("sports-sport")
    }

    /// League: All Leagues, then the chosen sport's competitions (followed first), racing series
    /// and cycling races.
    private var leagueMenu: some View {
        Menu {
            Picker("League", selection: $store.league) {
                Text("All Leagues").tag(SportsHubFilters.all)
                ForEach(store.leagueOptions) { Text($0.label).tag($0.id) }
            }
        } label: {
            Label(store.leagueLabel, systemImage: "chevron.down")
        }
        .buttonStyle(FilterChipStyle(selected: store.league != SportsHubFilters.all))
        .accessibilityIdentifier("sports-league")
    }
}

/// Under the controls while a sport or league is chosen (Expo TV's filter summary): what the
/// rows show, Competition Details (a league's standings and games, the race weekends, the
/// cycling calendar) and Clear Filters. Coming in from above or below lands on its first button.
struct SportsFilterSummary: View {
    @ObservedObject var store: SportsHubStore
    let spoilers: Bool
    let focus: FocusState<String?>.Binding

    var body: some View {
        HStack(spacing: 24) {
            Text(summary).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            if store.hasDetails {
                NavigationLink(value: SportsCompetitionRoute(sport: store.sport, league: store.league)) {
                    Text(browseAll ? "Browse All Cycling Dates" : "Competition Details")
                }
                .focused(focus, equals: "summary-details")
                .accessibilityIdentifier("sports-competition-details")
            }
            Button("Clear Filters") { store.clearFilters() }
                .focused(focus, equals: "summary-clear")
                .accessibilityIdentifier("sports-clear-filters")
        }
        .font(.callout)
        .sportsChipRow()
        .defaultFocus(focus, store.hasDetails ? "summary-details" : "summary-clear", priority: .userInitiated)
    }

    private var browseAll: Bool { store.sport == SportsCycling.sport && store.league == SportsHubFilters.all }

    private var summary: String {
        [store.sport == SportsHubFilters.all ? nil : SportsHubFilters.sportLabel(store.sport),
         store.league == SportsHubFilters.all ? nil : store.leagueLabel,
         store.followingOnly ? String(localized: "Following only") : nil,
         spoilers ? String(localized: "Scores hidden") : nil].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Value pushed to open Competition Details for the hub's chosen sport and league.
struct SportsCompetitionRoute: Hashable {
    let sport: String
    let league: String
}
