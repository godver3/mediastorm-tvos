#if os(iOS)
import SwiftUI

/// Customize Sports on a phone (Expo `SportsPreferencesEditor`), as a sheet: followed teams
/// (swipe to unfollow) with Add Team, pinned sports, then competitions by sport. Followed
/// competitions and pinned sports lead the hub's sections and fill Following; followed teams fill
/// My Teams. Each change saves at once to the profile's sports preferences
/// (`SportsPreferencesEditor`, shared with the TV and the Expo app).
struct MobileSportsPreferencesSheet: View {
    @ObservedObject var hub: SportsHubStore
    @StateObject private var editor: SportsPreferencesEditor
    @Environment(\.dismiss) private var dismiss

    init(hub: SportsHubStore) {
        self.hub = hub
        _editor = StateObject(wrappedValue: SportsPreferencesEditor { [weak hub] in hub?.preferences = $0 })
    }

    private var bySport: [(sport: String, leagues: [SportsLeague])] {
        Dictionary(grouping: hub.usableLeagues) { $0.sport ?? "other" }
            .map { (sport: $0.key, leagues: $0.value) }
            .sorted { $0.sport < $1.sport }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let message = editor.message {
                    Section { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary) }
                }
                if editor.loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if editor.envelope == nil {
                    ContentUnavailableView("Preferences Unavailable", systemImage: "slider.horizontal.3",
                                           description: Text("This server doesn't save sports preferences."))
                } else {
                    MobileSportsTeamsSection(hub: hub, editor: editor)
                    pins
                    ForEach(bySport, id: \.sport) { group in
                        Section(Self.sportName(group.sport)) {
                            ForEach(group.leagues) { league in
                                Toggle(league.label, isOn: follow(league))
                                    .accessibilityIdentifier("sports-follow-\(league.id)")
                            }
                        }
                    }
                }
            }
            .disabled(editor.saving)
            .navigationTitle("Customize Sports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .task { await editor.reload() }
    }

    /// Pinned sports lead the hub and its Sport menu, in the order they were pinned.
    private var pins: some View {
        Section {
            ForEach(SportsHubFilters.sportOptions(hub.catalog, pinned: [])) { option in
                Toggle(option.label, isOn: pin(option.id))
                    .accessibilityIdentifier("sports-pin-\(option.id)")
            }
        } header: {
            Text("Pinned Sports")
        } footer: {
            Text("Pinned sports and followed competitions come first on the hub and fill Following.")
        }
    }

    /// "mma" → "MMA", "rugby-league" → "Rugby League".
    static func sportName(_ id: String) -> String {
        id.count <= 3 ? id.uppercased() : id.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private func follow(_ league: SportsLeague) -> Binding<Bool> {
        Binding {
            editor.envelope?.preferences.competitionIds.contains(league.followID) ?? false
        } set: { on in
            Task {
                await editor.change { preferences in
                    var ids = preferences.competitionIds.filter { $0 != league.followID }
                    if on { ids.append(league.followID) }
                    preferences.competitionIds = ids
                }
            }
        }
    }

    private func pin(_ sport: String) -> Binding<Bool> {
        Binding {
            editor.envelope?.preferences.pinnedSportIds.contains(sport) ?? false
        } set: { on in
            Task {
                await editor.change { preferences in
                    var ids = preferences.pinnedSportIds.filter { $0 != sport }
                    if on { ids.append(sport) }
                    preferences.pinnedSportIds = ids
                }
            }
        }
    }
}

/// Customize › Teams: the followed teams (swipe or Edit to unfollow), then Add Team: a
/// competition, then its teams from the standings, searchable.
struct MobileSportsTeamsSection: View {
    @ObservedObject var hub: SportsHubStore
    @ObservedObject var editor: SportsPreferencesEditor

    var body: some View {
        Section {
            ForEach(editor.teamIDs, id: \.self) { id in
                Text(name(id))
                    .swipeActions {
                        Button("Unfollow", role: .destructive) {
                            Task { await editor.change { $0 = SportsTeamFollows.unfollowing($0, stored: id) } }
                        }
                    }
                    .accessibilityIdentifier("sports-followed-team-\(id)")
            }
            NavigationLink {
                MobileSportsAddTeamView(hub: hub, editor: editor)
            } label: {
                Label("Add Team", systemImage: "plus")
            }
            .accessibilityIdentifier("sports-add-team")
        } header: {
            Text("Teams")
        } footer: {
            Text("Followed teams fill My Teams. Swipe a team to unfollow it.")
        }
        .task(id: Set(editor.teamIDs.map(SportsTeamFollows.league))) {
            for league in Set(editor.teamIDs.map(SportsTeamFollows.league)).sorted() where !Task.isCancelled {
                await editor.loadStandings(league)
            }
        }
    }

    private func name(_ id: String) -> String {
        SportsTeamFollows.name(id, tables: hub.tables.merging(editor.standings) { _, new in new }, games: hub.games)
    }
}

/// Add Team, step one: the team-sport competitions, followed and pinned first.
struct MobileSportsAddTeamView: View {
    @ObservedObject var hub: SportsHubStore
    @ObservedObject var editor: SportsPreferencesEditor
    @State private var query = ""

    var body: some View {
        let preferences = editor.envelope?.preferences
        let leagues = SportsTeamFollows.teamLeagues(hub.catalog, followed: preferences?.competitionIds ?? [],
                                                    pinned: preferences?.pinnedSportIds ?? [])
            .filter { query.isEmpty || $0.label.localizedStandardContains(query) }
        List(leagues) { league in
            NavigationLink(league.label) { MobileSportsLeagueTeamsView(league: league, editor: editor) }
                .accessibilityIdentifier("sports-add-team-\(league.id)")
        }
        .overlay {
            if leagues.isEmpty, !query.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .searchable(text: $query, prompt: "Competitions")
        .navigationTitle("Add Team")
    }
}

/// Add Team, step two: the league's teams from its standings, searchable; each toggle follows or
/// unfollows the team at once (saved as `league:row.id`).
struct MobileSportsLeagueTeamsView: View {
    let league: SportsLeague
    @ObservedObject var editor: SportsPreferencesEditor
    @State private var query = ""

    var body: some View {
        List {
            if let message = editor.message { Text(message).foregroundStyle(.secondary) }
            if let tables = editor.standings[league.id] {
                let all = SportsTeamFollows.teams(tables)
                let teams = all.filter { query.isEmpty || $0.name.localizedStandardContains(query) }
                if all.isEmpty {
                    ContentUnavailableView("No Teams Yet", systemImage: "person.3",
                                           description: Text("Teams for this league aren't available yet — follow one from a game page."))
                } else if teams.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ForEach(teams) { row in
                        Toggle(row.name, isOn: binding(row))
                            .accessibilityIdentifier("sports-team-\(row.id)")
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .disabled(editor.saving)
        .searchable(text: $query, prompt: "Teams")
        .navigationTitle(league.label)
        .task { await editor.loadStandings(league.id) }
    }

    private func binding(_ row: SportsTableRow) -> Binding<Bool> {
        Binding {
            SportsTeamFollows.isFollowed(league: league.id, teamID: row.id, in: editor.teamIDs)
        } set: { on in
            Task { await editor.setTeam(league: league.id, teamID: row.id, followed: on) }
        }
    }
}
#endif
