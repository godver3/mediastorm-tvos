import SwiftUI

/// A rugby match's events (Expo `SportsRugbyTimeline`): tries, conversions, goals and cards
/// ("Scoring & Discipline"), or the substitutions, newest first by the minute. Six show; Select on
/// "Show All N Events" lists the rest. Each event: minute, mark (T, C, PG, YC…), title, side and
/// player. One stop per event.
struct SportsRugbyTimeline: View {
    let page: SportsGamePage
    var substitutions = false

    @State private var expanded = false

    static func plays(_ page: SportsGamePage, substitutions: Bool) -> [SportsPlay] {
        SportsRugby.latest(page.detail.plays.filter(substitutions ? SportsRugby.isSubstitution : SportsRugby.isKeyEvent))
    }

    static func shows(_ page: SportsGamePage, substitutions: Bool) -> Bool {
        page.lifecycle != .scheduled && (!substitutions || !plays(page, substitutions: true).isEmpty)
    }

    var body: some View {
        let plays = Self.plays(page, substitutions: substitutions)
        SportsPanel(substitutions ? String(localized: "Substitutions") : String(localized: "Scoring & Discipline")) {
            if plays.isEmpty {
                Text("The provider has not supplied a scoring timeline.").foregroundStyle(.secondary).sportsReadout()
            }
            ForEach(expanded ? plays : Array(plays.prefix(6))) { row($0) }
            if plays.count > 6 {
                Button(expanded ? String(localized: "Show Fewer Events") : String(localized: "Show All \(plays.count) Events")) {
                    expanded.toggle()
                }
                .buttonStyle(FilterChipStyle(selected: false))
                .font(.callout)
                .padding(.top, 6)
            }
        }
    }

    private func row(_ play: SportsPlay) -> some View {
        let team = page.team(id: play.teamId)
        let mark = SportsRugby.mark(play.title)
        let who = play.description ?? play.participants.map(\.name).joined(separator: ", ")
        return HStack(alignment: .top, spacing: 18) {
            Text(play.clock ?? "—").font(.callout).foregroundStyle(.secondary).monospacedDigit().frame(width: 70, alignment: .leading)
            Text(mark)
                .font(.caption.weight(.bold))
                .foregroundStyle(SportsRugby.markColor(mark) == nil ? Color.primary : Color.black)
                .frame(minWidth: 52, minHeight: 36)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SportsRugby.markColor(mark) ?? team.map { SportsTeamColors.color($0, in: page.game).opacity(0.35) }
                        ?? Color.white.opacity(0.1)))
            VStack(alignment: .leading, spacing: 3) {
                Text(play.title.sportsCapitalized).fontWeight(.semibold)
                let detail = [team?.name, who.isEmpty ? nil : who].compactMap { $0 }.joined(separator: " · ")
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .sportsReadout()
    }
}

/// The sides' named players (Expo `SportsRugbyLineups`): per side, "number · name · position ·
/// Starter|Replacement". One stop per player.
struct SportsRugbyLineups: View {
    let page: SportsGamePage

    static func shows(_ page: SportsGamePage) -> Bool { page.detail.lineups.contains { !$0.players.isEmpty } }

    var body: some View {
        SportsPanel(String(localized: "Lineups")) {
            ForEach(page.detail.lineups, id: \.teamId) { lineup in
                Text(page.team(id: lineup.teamId)?.name ?? String(localized: "Team not supplied"))
                    .font(.headline).padding(.top, 8)
                ForEach(lineup.players) { player in
                    Text([player.number, player.name, player.position,
                          player.starter ? String(localized: "Starter") : String(localized: "Replacement")]
                        .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                        .sportsReadout()
                }
            }
        }
    }
}
