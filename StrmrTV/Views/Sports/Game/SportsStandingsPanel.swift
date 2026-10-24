import SwiftUI

/// The Standings tab: the table snapshot sent with the game (Expo `SportsStandingsPanel`),
/// one group at a time when there are several (conferences), this game's sides highlighted.
/// Soccer tables show played, goal difference and points; others conference and overall
/// records. Expo's team search is left out on TV.
struct SportsStandingsPanel: View {
    let page: SportsGamePage

    @State private var groupIndex = 0
    @FocusState private var chipFocus: Int?

    var body: some View {
        let groups = page.detail.standings
        let index = groups.indices.contains(groupIndex) ? groupIndex : 0
        let soccer = page.kind == .soccer
        VStack(alignment: .leading, spacing: 24) {
            if groups.count > 1 {
                HStack(spacing: 18) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { offset, group in
                        Button(Self.chipLabel(group.title)) { groupIndex = offset }
                            .buttonStyle(FilterChipStyle(selected: offset == index))
                            .focused($chipFocus, equals: offset)
                    }
                }
                .font(.callout)
                .sportsChipRow()
                .defaultFocus($chipFocus, index, priority: .userInitiated)
            }
            if groups.indices.contains(index) {
                let group = groups[index]
                SportsPanel(group.title.isEmpty ? String(localized: "Standings") : group.title,
                            note: String(localized: "Table snapshot supplied with the feed · May be newer than this game")) {
                    row(rank: "#", name: String(localized: "Team"), values: soccer ? ["GP", "GD", "PTS"] : ["CONF", "OVERALL"], soccer: soccer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Array(group.rows.enumerated()), id: \.offset) { _, team in
                        let playing = team.teamId == page.game.homeTeam.id || team.teamId == page.game.awayTeam.id
                        let values = soccer ? [team.played, team.goalDifference, team.points] : [team.conferenceRecord, team.record]
                        row(rank: team.rank ?? "–", name: team.name,
                            values: values.map { $0.flatMap { $0.isEmpty ? nil : $0 } ?? "–" }, soccer: soccer)
                            .fontWeight(playing ? .bold : .regular)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(playing ? 0.1 : 0)).padding(.horizontal, -10))
                            .sportsReadout()
                    }
                    Text(soccer ? "GP: games played · GD: goal difference · PTS: points. A dash means the value was not supplied."
                         : "CONF: conference record · OVERALL: overall record. A dash means the value was not supplied.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }
                .frame(maxWidth: 1300, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(rank: String, name: String, values: [String], soccer: Bool) -> some View {
        HStack(spacing: 0) {
            Text(rank).frame(width: 70, alignment: .leading)
            Text(name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Text(value).lineLimit(1).frame(width: soccer ? 110 : 170, alignment: .trailing)
            }
        }
        .monospacedDigit()
    }

    /// A group's chip: its title without the season and "Standings" ("Big Ten Conference").
    nonisolated static func chipLabel(_ title: String) -> String {
        title.replacingOccurrences(of: #"^\d{4}(?:-\d{2})? "#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #" Standings$"#, with: "", options: .regularExpression)
    }
}
