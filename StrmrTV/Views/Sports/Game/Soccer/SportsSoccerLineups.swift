import SwiftUI

/// The Lineups tab of soccer matches (Expo `SportsGameDetailTV`'s lineups tab): the published
/// formations on the pitch over both sides' players, beside the match's goals and its first three
/// statistics when the feed has events. Each column is a focus section.
struct SportsLineupsPanel: View {
    let page: SportsGamePage

    var body: some View {
        let side = !page.detail.plays.isEmpty
        SportsColumns(weights: side ? [2, 1] : [1]) {
            VStack(alignment: .leading, spacing: 24) {
                SportsSoccerPitch(page: page)
                SportsLineupLists(page: page)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .focusSection()
            if side {
                VStack(alignment: .leading, spacing: 24) {
                    SportsSoccerGoals(page: page)
                    if !page.detail.comparisons.isEmpty {
                        SportsSoccerStats(page: page, rows: Array(page.detail.comparisons.prefix(3)))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .focusSection()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The match's goals, newest first (Expo `PlaysPanel` in its highlights mode): minute, side, scorer
/// and narrative, in the scoring side's colour. One stop per goal.
struct SportsSoccerGoals: View {
    let page: SportsGamePage

    var body: some View {
        let goals = page.detail.plays.filter { SportsEventKind(title: $0.title) == .goal || $0.scoring }
        SportsPanel(String(localized: "Goals"),
                    note: goals.isEmpty ? nil : String(localized: "Newest first · Every key event in Commentary")) {
            if goals.isEmpty {
                Text("No goals in the loaded feed.").foregroundStyle(.secondary).sportsReadout()
            }
            ForEach(goals) { play in
                let team = page.team(id: play.teamId)
                HStack(alignment: .top, spacing: 16) {
                    SportsSoccerEventIcon(play: play, color: team.map { SportsTeamColors.color($0, in: page.game) } ?? .secondary, size: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        Text([play.clock, team?.shortName, play.shootout ? String(localized: "Shootout") : nil]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(SportsStatusPill.accent).monospacedDigit()
                        Text(play.participants.first?.name ?? play.title).fontWeight(.semibold)
                        if let description = play.description {
                            Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .sportsReadout()
            }
        }
    }
}
