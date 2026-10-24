import SwiftUI

/// The Overview of ATP and WTA matches (Expo `SportsSportOverview`'s tennis branch): the set
/// scores and the latest match action beside the serve and return statistics and the match's
/// draw, court, format, venue and channels. A match not under way opens with the availability
/// notice; a scheduled one ends with the matchup preview.
struct SportsTennisOverview: View {
    let page: SportsGamePage

    private enum Panel: Hashable { case availability, sets, action, stats, info }

    var body: some View {
        let left = [Panel.availability, .sets, .action].filter(shows)
        let right = [Panel.stats, .info].filter(shows)
        VStack(alignment: .leading, spacing: 40) {
            SportsColumns(weights: [1.2, 1]) {
                if !left.isEmpty { column(left) }
                if !right.isEmpty { column(right) }
            }
            if page.lifecycle == .scheduled {
                SportsPregamePreview(page: page, pregame: page.detail.pregame)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func column(_ panels: [Panel]) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(panels, id: \.self) { panel($0) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .focusSection()
    }

    /// "US Open · Men's Singles · 1st Round · Arthur Ashe Stadium · Best of 5 sets", then where and on
    /// which channels (Expo's tennis `EventInfo`).
    private var info: [String] {
        let game = page.game
        let format = game.bestOf.flatMap { [3, 5].contains($0) ? String(localized: "Best of \($0) sets") : nil }
        return [[SportsTennis.eventContext(game), game.courtName, format], [game.venue, game.broadcasts?.joined(separator: " · ")]]
            .map { $0.compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ") }
            .filter { !$0.isEmpty }
    }

    private func shows(_ panel: Panel) -> Bool {
        let started = page.lifecycle != .scheduled
        switch panel {
        case .availability: return SportsAvailabilityNotice.applies(page)
        case .sets: return started && !page.detail.periods.isEmpty
        case .action: return !page.detail.plays.isEmpty
        case .stats: return started && !page.detail.comparisons.isEmpty
        case .info: return !info.isEmpty || page.coverageNote != nil
        }
    }

    @ViewBuilder private func panel(_ panel: Panel) -> some View {
        switch panel {
        case .availability: SportsAvailabilityNotice(page: page)
        case .sets: SportsTennisSetScores(page: page)
        case .action: SportsKeyEvents(page: page, title: String(localized: "Match Action"))
        case .stats:
            SportsTeamComparison(page: page, rows: SportsTeamComparison.priorityRows(page), title: SportsTeamComparison.title(page.kind))
        case .info:
            SportsPanel(String(localized: "Match Information")) {
                if !info.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(info, id: \.self) { Text($0) }
                    }
                    .sportsReadout()
                }
                if let note = page.coverageNote {
                    Text(note).font(.caption).foregroundStyle(.secondary).sportsReadout()
                }
            }
        }
    }
}

/// The latest events of a match (Expo `KeyEvents`): up to four, newest first, each with when it
/// happened, its title and the narrative; scoring ones marked in the accent. One stop each.
struct SportsKeyEvents: View {
    let page: SportsGamePage
    let title: String

    var body: some View {
        SportsPanel(title) {
            ForEach(page.detail.plays.prefix(4)) { play in
                HStack(alignment: .top, spacing: 18) {
                    Capsule().fill(play.scoring ? SportsStatusPill.accent : Color.white.opacity(0.25)).frame(width: 4)
                    VStack(alignment: .leading, spacing: 4) {
                        let time = [play.periodLabel, play.clock].compactMap { $0?.isEmpty == false ? $0 : nil }
                        if !time.isEmpty { Text(time.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                        Text(play.title).fontWeight(.semibold)
                        if let description = play.description { Text(description).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .sportsReadout()
            }
        }
    }
}
