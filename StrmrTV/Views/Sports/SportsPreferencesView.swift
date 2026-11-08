import SwiftUI

/// Follow competitions, grouped by sport, then teams (`SportsTeamsSection`). Followed
/// competitions sort first on the hub and fill its Following filter; followed teams fill My
/// Teams. Each change saves at once to the profile's sports preferences, shared with the Expo
/// app; ids this screen doesn't know (schools, cycling races) are kept as they are.
struct SportsPreferencesView: View {
    @ObservedObject var hub: SportsHubStore
    @StateObject private var editor: SportsPreferencesEditor

    init(hub: SportsHubStore) {
        self.hub = hub
        _editor = StateObject(wrappedValue: SportsPreferencesEditor { [weak hub] in hub?.preferences = $0 })
    }

    private var leagues: [SportsLeague] { hub.usableLeagues }

    private var bySport: [(sport: String, leagues: [SportsLeague])] {
        Dictionary(grouping: leagues) { $0.sport ?? "other" }
            .map { (sport: $0.key, leagues: $0.value) }
            .sorted { $0.sport < $1.sport }
    }

    var body: some View {
        Form {
            SettingsPageTitle("Follow Competitions")
            if let message = editor.message { Text(message).foregroundStyle(.secondary) }
            if editor.loading {
                ProgressView()
            } else if editor.envelope == nil {
                Text("This server doesn't save sports preferences.").foregroundStyle(.secondary)
            } else {
                ForEach(bySport, id: \.sport) { group in
                    Section(Self.sportName(group.sport)) {
                        ForEach(group.leagues) { league in
                            Toggle(league.label, isOn: binding(league))
                                .disabled(editor.saving)
                                .accessibilityIdentifier("sports-follow-\(league.id)")
                        }
                    }
                }
                SportsTeamsSection(hub: hub, editor: editor)
            }
        }
        .settingsListMargins(50)
        .padding(.horizontal, 30)
        .settingsSubpage()
        .task { await editor.reload() }
    }

    /// "mma" → "MMA", "rugby-league" → "Rugby League".
    private static func sportName(_ id: String) -> String {
        id.count <= 3 ? id.uppercased() : id.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private func binding(_ league: SportsLeague) -> Binding<Bool> {
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
}
