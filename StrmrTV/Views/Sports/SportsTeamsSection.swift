import SwiftUI

/// Customize › Teams: the followed teams, each with Unfollow, then Add Team (a league, then its
/// teams from the standings). Followed teams fill the hub's My Teams filter.
struct SportsTeamsSection: View {
    @ObservedObject var hub: SportsHubStore
    @ObservedObject var editor: SportsPreferencesEditor
    @FocusState private var addFocused: Bool

    var body: some View {
        Section("Teams") {
            ForEach(editor.teamIDs, id: \.self) { id in
                Button {
                    // The row goes away: focus moves on to Add Team.
                    addFocused = true
                    Task { await editor.change { $0 = SportsTeamFollows.unfollowing($0, stored: id) } }
                } label: {
                    HStack {
                        Text(name(id))
                        Spacer()
                        Text("Unfollow").foregroundStyle(.secondary)
                    }
                }
                .disabled(editor.saving)
                .accessibilityIdentifier("sports-unfollow-team-\(id)")
            }
            NavigationLink {
                SportsAddTeamView(hub: hub, editor: editor)
            } label: {
                Label("Add Team", systemImage: "plus")
            }
            .focused($addFocused)
            .accessibilityIdentifier("sports-add-team")
        }
        // Names from the standings of the followed teams' leagues.
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
struct SportsAddTeamView: View {
    @ObservedObject var hub: SportsHubStore
    @ObservedObject var editor: SportsPreferencesEditor

    var body: some View {
        Form {
            SettingsPageTitle("Add Team")
            let preferences = editor.envelope?.preferences
            ForEach(SportsTeamFollows.teamLeagues(hub.catalog, followed: preferences?.competitionIds ?? [],
                                                  pinned: preferences?.pinnedSportIds ?? [])) { league in
                NavigationLink(league.label) { SportsLeagueTeamsView(league: league, editor: editor) }
                    .accessibilityIdentifier("sports-add-team-\(league.id)")
            }
        }
        .settingsListMargins(50)
        .padding(.horizontal, 30)
        .settingsSubpage()
    }
}

/// Add Team, step two: the league's teams from its standings, by name; selecting one follows
/// or unfollows it (saved as `league:row.id`).
struct SportsLeagueTeamsView: View {
    let league: SportsLeague
    @ObservedObject var editor: SportsPreferencesEditor

    var body: some View {
        Form {
            SettingsPageTitle(Text(verbatim: league.label))
            if let message = editor.message { Text(message).foregroundStyle(.secondary) }
            if let tables = editor.standings[league.id] {
                let teams = SportsTeamFollows.teams(tables)
                if teams.isEmpty {
                    Text("Teams for this league aren't available yet — follow one from a game page.").foregroundStyle(.secondary)
                } else {
                    ForEach(teams) { row in
                        Toggle(row.name, isOn: binding(row))
                            .disabled(editor.saving)
                            .accessibilityIdentifier("sports-team-\(row.id)")
                    }
                }
            } else {
                ProgressView()
            }
        }
        .settingsListMargins(50)
        .padding(.horizontal, 30)
        .settingsSubpage()
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
