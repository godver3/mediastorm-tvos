import SwiftUI

/// A play on NFL and college football's Play-by-Play tab (Expo `FootballPlays`): the quarter over
/// the clock, a timeline marker (a gold diamond for a score), the side's logo, then the play's
/// title, the narrative and a gold "Scoring Play" tag.
struct SportsFootballPlayRow: View {
    let page: SportsGamePage
    let play: SportsPlay

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(play.periodLabel).font(.caption).foregroundStyle(.secondary)
                Text(play.clock ?? "").fontWeight(.semibold).monospacedDigit()
            }
            .frame(width: 90, alignment: .leading)
            ZStack {
                // The timeline runs on through the gaps between rows.
                Rectangle().fill(Color.white.opacity(0.18)).frame(width: 2).frame(maxHeight: .infinity).padding(.vertical, -16)
                Image(systemName: play.scoring ? "diamond.fill" : "circle.fill")
                    .font(.system(size: play.scoring ? 20 : 10))
                    .foregroundStyle(play.scoring ? SportsTeamColors.scoring : Color.secondary)
            }
            .frame(width: 26)
            .accessibilityHidden(true)
            Group {
                if let team = page.team(id: play.teamId) { SportsTeamLogo(team: team, size: 48) } else { Color.clear }
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(play.title).fontWeight(.semibold)
                if let description = play.description?.trimmingCharacters(in: .whitespaces), description != play.title {
                    Text(description).foregroundStyle(.secondary).lineLimit(4)
                }
                if play.scoring {
                    Text("Scoring Play").font(.caption2.weight(.bold)).foregroundStyle(SportsTeamColors.scoring)
                }
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .sportsReadout()
    }
}
