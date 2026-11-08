#if os(iOS)
import SwiftUI

/// The hub's filters (Expo's mobile header and Filters panel): All / Live / Upcoming / Results
/// as a segmented control, then a row of chips: the day (when the server answers other days),
/// the sport and the competition as menus (pinned sports and followed competitions first), and
/// Following and My Teams, which are exclusive. The chip row scrolls sideways when it outgrows
/// the screen.
struct MobileSportsHubControls: View {
    @ObservedObject var store: SportsHubStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Show", selection: $store.filter) {
                ForEach(SportsFilter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("sports-filter")
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    if store.dated { dayMenu }
                    sportMenu
                    leagueMenu
                    chip("Following", symbol: store.followingOnly ? "star.fill" : "star", on: store.followingOnly) {
                        store.followingOnly.toggle()
                    }
                    .accessibilityIdentifier("sports-following")
                    chip("My Teams", symbol: store.myTeamsOnly ? "person.2.fill" : "person.2", on: store.myTeamsOnly) {
                        store.myTeamsOnly.toggle()
                    }
                    .accessibilityIdentifier("sports-my-teams")
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .padding(.horizontal, -16)
        }
        .padding(.top, 4)
    }

    private var dayMenu: some View {
        Menu {
            Picker("Day", selection: $store.day) {
                ForEach(SportsDay.allCases) { day in
                    Text(MobileSportsHubControls.dayLabel(day)).tag(day)
                }
            }
        } label: {
            MobileSportsChipLabel(title: store.day.label, symbol: "calendar", on: store.day != .today, menu: true)
        }
        .accessibilityIdentifier("sports-day")
    }

    /// "Tomorrow · Nov 9".
    static func dayLabel(_ day: SportsDay) -> String {
        "\(day.label) · \(day.interval.start.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var sportMenu: some View {
        Menu {
            Picker("Sport", selection: Binding(get: { store.sport }, set: { store.chooseSport($0) })) {
                Text(SportsHubFilters.sportLabel(SportsHubFilters.all)).tag(SportsHubFilters.all)
                ForEach(store.sportOptions) { Text($0.label).tag($0.id) }
            }
        } label: {
            MobileSportsChipLabel(title: SportsHubFilters.sportLabel(store.sport), symbol: nil,
                                  on: store.sport != SportsHubFilters.all, menu: true)
        }
        .accessibilityIdentifier("sports-sport")
    }

    private var leagueMenu: some View {
        Menu {
            Picker("Competition", selection: $store.league) {
                Text("All Leagues").tag(SportsHubFilters.all)
                ForEach(store.leagueOptions) { Text($0.label).tag($0.id) }
            }
        } label: {
            MobileSportsChipLabel(title: store.leagueLabel, symbol: nil, on: store.league != SportsHubFilters.all, menu: true)
        }
        .accessibilityIdentifier("sports-league")
    }

    private func chip(_ title: String.LocalizationValue, symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            MobileSportsChipLabel(title: String(localized: title), symbol: symbol, on: on)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A filter chip: a capsule, tinted while it narrows the hub; a menu chip ends in a chevron.
struct MobileSportsChipLabel: View {
    let title: String
    let symbol: String?
    let on: Bool
    var menu = false

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(title).lineLimit(1)
            if menu { Image(systemName: "chevron.down").imageScale(.small).font(.caption.weight(.semibold)) }
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .foregroundStyle(on ? Color.white : Color.primary)
        .background(Capsule().fill(on ? Color.accentColor : Color(.tertiarySystemFill)))
        .contentShape(Capsule())
    }
}

/// Under the controls while a sport or competition is chosen (Expo's filter summary): what the
/// cards show, Competition Details (standings and games, the race weekends, the cycling
/// calendar) and Clear Filters.
struct MobileSportsFilterSummary: View {
    @ObservedObject var store: SportsHubStore
    let spoilers: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summary).font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                if store.hasDetails {
                    NavigationLink(value: SportsCompetitionRoute(sport: store.sport, league: store.league)) {
                        Label(browseAll ? "Browse All Cycling Dates" : "Competition Details", systemImage: "list.number")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("sports-competition-details")
                }
                Button("Clear Filters") { store.clearFilters() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("sports-clear-filters")
            }
            .controlSize(.small)
        }
    }

    private var browseAll: Bool { store.sport == SportsCycling.sport && store.league == SportsHubFilters.all }

    private var summary: String {
        [store.sport == SportsHubFilters.all ? nil : SportsHubFilters.sportLabel(store.sport),
         store.league == SportsHubFilters.all ? nil : store.leagueLabel,
         store.followingOnly ? String(localized: "Following only") : nil,
         store.myTeamsOnly ? String(localized: "My Teams only") : nil,
         spoilers ? String(localized: "Scores hidden") : nil].compactMap { $0 }.joined(separator: " · ")
    }
}
#endif
