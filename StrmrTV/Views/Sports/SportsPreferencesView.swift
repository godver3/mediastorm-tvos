import SwiftUI

/// Follow competitions, grouped by sport. Followed competitions sort first on the hub and
/// fill its Following filter. Each change saves at once to the profile's sports preferences,
/// shared with the Expo app; ids this screen doesn't know (teams, schools, cycling races)
/// are kept as they are.
struct SportsPreferencesView: View {
    let leagues: [SportsLeague]
    let onSaved: (SportsPreferencesEnvelope) -> Void

    @State private var envelope: SportsPreferencesEnvelope?
    @State private var loading = true
    @State private var saving = false
    @State private var message: String?

    private var bySport: [(sport: String, leagues: [SportsLeague])] {
        Dictionary(grouping: leagues) { $0.sport ?? "other" }
            .map { (sport: $0.key, leagues: $0.value) }
            .sorted { $0.sport < $1.sport }
    }

    var body: some View {
        Form {
            SettingsPageTitle("Follow Competitions")
            if let message { Text(message).foregroundStyle(.secondary) }
            if loading {
                ProgressView()
            } else if envelope == nil {
                Text("This server doesn't save sports preferences.").foregroundStyle(.secondary)
            } else {
                ForEach(bySport, id: \.sport) { group in
                    Section(Self.sportName(group.sport)) {
                        ForEach(group.leagues) { league in
                            Toggle(league.label, isOn: binding(league))
                                .disabled(saving)
                                .accessibilityIdentifier("sports-follow-\(league.id)")
                        }
                    }
                }
            }
        }
        .settingsListMargins(50)
        .padding(.horizontal, 30)
        .settingsSubpage()
        .task { await reload() }
    }

    /// "mma" → "MMA", "rugby-league" → "Rugby League".
    private static func sportName(_ id: String) -> String {
        id.count <= 3 ? id.uppercased() : id.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private func binding(_ league: SportsLeague) -> Binding<Bool> {
        Binding {
            envelope?.preferences.competitionIds.contains(league.followID) ?? false
        } set: { on in
            Task { await save(league.followID, on: on) }
        }
    }

    private func reload() async {
        envelope = try? await APIClient.shared.sportsPreferences()
        loading = false
    }

    private func save(_ id: String, on: Bool) async {
        guard var next = envelope else { return }
        var ids = next.preferences.competitionIds.filter { $0 != id }
        if on { ids.append(id) }
        next.preferences.competitionIds = ids
        saving = true
        defer { saving = false }
        do {
            let saved = try await APIClient.shared.saveSportsPreferences(next)
            envelope = saved
            message = nil
            onSaved(saved)
        } catch let APIError.http(failure) where failure.status == 409 {
            message = String(localized: "Another device changed these. Reloaded the saved list.")
            await reload()
        } catch {
            message = error.localizedDescription
        }
    }
}
