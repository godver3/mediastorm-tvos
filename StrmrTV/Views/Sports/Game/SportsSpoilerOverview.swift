import SwiftUI

/// The page with scores hidden (Expo `SportsSpoilerOverview`): the matchup, when and where it
/// is played and on which channels, then the matchup preview cut to what was known before
/// the start. No tabs, scores, records or game stats. Fights keep their card without results.
struct SportsSpoilerOverview: View {
    let page: SportsGamePage

    var body: some View {
        if page.kind == .mma || page.kind == .boxing {
            SportsCombatOverview(page: page, hidden: true)
        } else {
            spoilerSafe
        }
    }

    private var spoilerSafe: some View {
        VStack(alignment: .leading, spacing: 36) {
            SportsPanel(nil) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(matchup).font(.headline)
                    ForEach(facts, id: \.self) { Text($0).foregroundStyle(.secondary) }
                    Text("Current game scores and stats hidden").font(.caption).foregroundStyle(.tertiary)
                }
                .sportsReadout()
            }
            .frame(maxWidth: 1100, alignment: .leading)
            if let pregame = page.detail.pregame?.spoilerSafe(start: page.game.start, eventID: page.game.id) {
                SportsPregamePreview(page: page, pregame: pregame, spoilerSafe: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var matchup: String {
        page.game.isMatchup ? "\(page.game.awayTeam.name) · \(page.game.homeTeam.name)" : page.game.displayTitle
    }

    private var facts: [String] {
        let game = page.game
        return [SportsFormat.startDate(game), game.start.formatted(date: .omitted, time: .shortened), game.venue,
                game.broadcasts?.joined(separator: " · ")]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
    }
}

extension SportsPregame {
    /// Only what was known before the game (Expo `sportsSpoilerContext`): a snapshot taken
    /// before the start keeps its records, standings and comparisons; a later one keeps only
    /// earlier results. This game itself and later meetings never show.
    func spoilerSafe(start: Date, eventID: String) -> SportsPregame {
        let before = { (date: String) in SportsGame.date(date).map { $0 < start } ?? false }
        let historical = updatedAt.map(before) ?? false
        var safe = SportsPregame(seasonLabel: seasonLabel, updatedAt: updatedAt)
        safe.teams = teams.map { team in
            var kept = historical ? team : SportsPregameTeam(teamId: team.teamId)
            kept.recent = team.recent.filter { $0.id != eventID && before($0.date) }
            return kept
        }
        safe.comparisons = historical ? comparisons : []
        safe.previousMeeting = previousMeeting.flatMap { before($0.date) ? $0 : nil }
        return safe
    }
}
