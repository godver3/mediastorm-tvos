import SwiftUI

/// A play: when (period and clock), what happened and the narrative. Scoring plays stand out
/// with a bar and a tint in the scoring side's colour (Expo's play rows mark baseball's
/// scoring plays the same way).
struct SportsPlayRow: View {
    let page: SportsGamePage
    let play: SportsPlay
    /// One line of narrative under the time, as the Overview's key plays show it.
    var compact = false
    /// The side's logo before a compact row (Expo `FootballRecentPlays`).
    var teamMark = false

    var body: some View {
        let color = play.scoring ? scoringColor : Color.clear
        HStack(alignment: .top, spacing: 22) {
            Capsule().fill(color).frame(width: 6).frame(maxHeight: .infinity)
            if compact {
                if teamMark, let team = page.team(id: play.teamId) { SportsTeamLogo(team: team, size: 40) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(time(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    Text((play.description ?? play.title).trimmingCharacters(in: .whitespaces))
                        .fontWeight(play.scoring ? .semibold : .regular).lineLimit(3)
                }
            } else {
                Text(time(separator: "\n")).font(.caption).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        Text(play.title).fontWeight(play.scoring ? .bold : .semibold)
                        if play.scoring {
                            Text("Scoring Play").font(.caption2.weight(.bold)).foregroundStyle(SportsTeamColors.scoring)
                        }
                    }
                    if page.game.league == "nhl", let badge = SportsHockeyGoalBadge(play) { SportsHockeyGoalBadgeTag(badge: badge) }
                    if let description = play.description?.trimmingCharacters(in: .whitespaces), description != play.title {
                        Text(description).foregroundStyle(.secondary).lineLimit(4)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.14)).padding(.horizontal, -12))
        .sportsReadout()
    }

    private func time(separator: String) -> String {
        [play.periodLabel, play.clock].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: separator)
    }

    /// The scoring side's colour, else the page's accent.
    private var scoringColor: Color {
        page.team(id: play.teamId).map { SportsTeamColors.color($0, in: page.game) } ?? Color.accentColor
    }
}

/// The Overview's key plays (Expo `RecentDetailPlays`, `FootballRecentPlays` with the sides'
/// logos): a final's scoring plays, else the newest plays (baseball without its pitch-by-pitch
/// lines); three at most, newest first.
struct SportsKeyPlays: View {
    let page: SportsGamePage
    var teamMarks = false

    var body: some View {
        let shown = Self.plays(page)
        SportsPanel(shown.title) {
            ForEach(shown.plays) { SportsPlayRow(page: page, play: $0, compact: true, teamMark: teamMarks) }
        }
    }

    nonisolated static func plays(_ page: SportsGamePage) -> (title: String, plays: [SportsPlay]) {
        let plays = page.detail.plays
        let final = page.lifecycle == .final
        let picked = final ? plays.filter(\.scoring)
            : page.game.league == "mlb" ? plays.filter { !SportsFormat.matches(#"^pitch\s*\d*\s*:"#, $0.title) }
            : plays
        let title = final && !picked.isEmpty ? String(localized: "Scoring Plays") : String(localized: "Recent Plays")
        return (title, Array((picked.isEmpty ? Array(plays.prefix(1)) : picked).prefix(3)))
    }
}
