import SwiftUI

/// The soccer sides' players (Expo `SportsLineupsPanel`, wide): starters, substitutes or the
/// reported changes, both sides next to each other with their formation, each player's number,
/// name, position and whether they came on or went off. Under the pitch on the Lineups tab.
struct SportsLineupLists: View {
    let page: SportsGamePage

    enum Selection: Hashable { case starters, bench, changes }

    @State private var selection: Selection = .starters
    @FocusState private var chipFocus: Selection?

    var body: some View {
        let lineups = page.detail.lineups
        let hasChanges = lineups.contains { $0.players.contains { $0.subbedIn || $0.subbedOut } }
        let choices: [Selection] = hasChanges ? [.starters, .bench, .changes] : [.starters, .bench]
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 18) {
                ForEach(choices, id: \.self) { choice in
                    Button(Self.label(choice)) { selection = choice }
                        .buttonStyle(FilterChipStyle(selected: selection == choice))
                        .focused($chipFocus, equals: choice)
                }
            }
            .font(.callout)
            .sportsChipRow()
            .defaultFocus($chipFocus, selection, priority: .userInitiated)
            SportsColumns {
                ForEach(page.teams, id: \.id) { team in
                    teamList(team, lineup: lineups.first { $0.teamId == team.id }).focusSection()
                }
            }
            Text("Reported match selection · Starting roles remain unchanged after substitutions")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func label(_ selection: Selection) -> String {
        switch selection {
        case .starters: String(localized: "Starters")
        case .bench: String(localized: "Substitutes")
        case .changes: String(localized: "Changes")
        }
    }

    private func teamList(_ team: SportsTeam, lineup: SportsLineup?) -> some View {
        let players = lineup?.players.filter { player in
            switch selection {
            case .starters: player.starter
            case .bench: !player.starter
            case .changes: player.subbedIn || player.subbedOut
            }
        } ?? []
        let heading = switch selection {
        case .starters: String(localized: "Starting XI")
        case .bench: String(localized: "Substitutes")
        case .changes: String(localized: "Reported changes")
        }
        return SportsPanel(nil) {
            HStack(spacing: 16) {
                SportsTeamLogo(team: team, size: 48)
                Text(team.name).font(.headline)
            }
            Text(lineup?.formation.map { String(localized: "Formation · \($0)") } ?? String(localized: "Formation unavailable"))
                .font(.caption).foregroundStyle(.secondary)
            Text("\(heading) · \(players.count == 1 ? String(localized: "1 player") : String(localized: "\(players.count) players"))")
                .font(.caption).foregroundStyle(.secondary)
            if players.isEmpty {
                Text(selection == .changes ? "No substitution changes supplied for this team." : "This selection is not available from the feed.")
                    .foregroundStyle(.secondary).sportsReadout()
            }
            ForEach(players) { player in
                HStack(spacing: 18) {
                    Text(player.number ?? "–").fontWeight(.bold).foregroundStyle(Color.accentColor).frame(width: 56, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.name).lineLimit(1)
                        Text(player.position ?? String(localized: "Position unavailable")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    if player.subbedIn || player.subbedOut {
                        Text([player.subbedIn ? String(localized: "↑ Came on") : nil, player.subbedOut ? String(localized: "↓ Went off") : nil]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(Color.accentColor)
                    }
                }
                .sportsReadout()
            }
        }
    }
}
