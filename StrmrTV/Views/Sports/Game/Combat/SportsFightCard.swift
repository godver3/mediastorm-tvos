import SwiftUI

/// The whole fight card in the feed's order (Expo "Fight card" with `SportsCombatBoutRow`): each
/// bout's fighters, division and result; the bout on screen says "Viewing", every other one opens
/// its own page on Select. Results are left out with scores hidden.
struct SportsFightCard: View {
    let page: SportsGamePage
    var hidden = false

    var body: some View {
        let bouts = page.game.combat?.bouts ?? []
        SportsPanel(String(localized: "Fight Card"),
                    note: bouts.isEmpty ? nil : String(localized: "Provider order · Main card and prelim sections are not supplied.")) {
            if bouts.isEmpty {
                Text("The provider has not supplied the full fight card.").foregroundStyle(.secondary).sportsReadout()
            }
            ForEach(bouts) { bout in
                if bout.id == page.game.id {
                    row(bout, viewing: true)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(SportsStatusPill.accent.opacity(0.7), lineWidth: 2))
                        .sportsReadout()
                } else {
                    NavigationLink(value: SportsGameRef(id: bout.id, title: names(bout))) {
                        row(bout, viewing: false)
                    }
                    .buttonStyle(SportsReadoutButtonStyle())
                    .accessibilityIdentifier("sports-bout-\(bout.id)")
                }
            }
        }
    }

    private func names(_ bout: SportsCombatBout) -> String { "\(bout.away.name) vs \(bout.home.name)" }

    private func row(_ bout: SportsCombatBout, viewing: Bool) -> some View {
        let line = [bout.division, SportsCombatRules.result(bout, hidden: hidden)].compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(names(bout)).font(.callout.weight(.semibold)).lineLimit(2)
                Spacer(minLength: 8)
                if viewing { Text("Viewing").font(.caption.weight(.semibold)).foregroundStyle(SportsStatusPill.accent) }
            }
            if !line.isEmpty { Text(line).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The scoreboard of a bout or fight card (Expo `SportsCombatHeader`): both fighters' portraits and
/// names either side of "VS" with the result, or the card's title when the fighters aren't named;
/// before the fight the division and start. With scores hidden the result says so.
struct SportsCombatHeader: View {
    let page: SportsGamePage
    let spoilers: Bool

    var body: some View {
        let game = page.game
        VStack(spacing: 18) {
            if SportsCombatRules.named(game) {
                HStack(spacing: 40) {
                    fighter(game.awayTeam, trailing: false)
                    Text("VS").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                    fighter(game.homeTeam, trailing: true)
                }
            } else {
                Text(game.displayTitle).font(.system(size: 52, weight: .semibold)).multilineTextAlignment(.center)
            }
            Text(line).font(.headline).multilineTextAlignment(.center)
        }
    }

    private var line: String {
        let game = page.game
        if page.lifecycle == .scheduled {
            return [game.combat?.division, SportsFormat.detailStatus(page)].compactMap { $0 }.joined(separator: " · ")
        }
        if spoilers { return SportsCombatRules.result(game, hidden: true) }
        if SportsCombatRules.named(game) { return SportsCombatRules.result(game, hidden: false) }
        return game.statusDetail.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Result not supplied")
    }

    private func fighter(_ athlete: SportsTeam, trailing: Bool) -> some View {
        let won = !spoilers && page.lifecycle == .final && athlete.winner == true
        let portrait = SportsPlayerPortrait(name: athlete.name,
                                            headshot: SportsCombatRules.portrait(league: page.game.league, fighter: athlete), size: 120)
        let text = VStack(alignment: trailing ? .leading : .trailing, spacing: 6) {
            Text(athlete.name).font(.title3.weight(.semibold)).lineLimit(2).multilineTextAlignment(trailing ? .leading : .trailing)
            if won { Text("WINNER").font(.caption.weight(.bold)).foregroundStyle(SportsCombatHeader.winner) }
        }
        return HStack(spacing: 24) {
            if trailing { portrait; text } else { text; portrait }
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .leading : .trailing)
    }

    /// Expo's winner tag colour (#b9dccb).
    static let winner = Color(red: 0.73, green: 0.86, blue: 0.80)
}
