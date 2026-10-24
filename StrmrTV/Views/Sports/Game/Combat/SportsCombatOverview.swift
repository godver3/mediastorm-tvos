import SwiftUI

/// The Overview of UFC bouts and boxing cards (Expo `SportsCombatOverview`): the fighters with
/// their portraits and records, the division, scheduled rounds, result, when and where, the tale
/// of the tape and the fight statistics, beside the whole fight card (each other bout opens its
/// own page). With scores hidden (`hidden`, the spoiler view) records, results and statistics
/// are left out.
struct SportsCombatOverview: View {
    let page: SportsGamePage
    var hidden = false

    var body: some View {
        SportsColumns(weights: [1.2, 1]) {
            VStack(alignment: .leading, spacing: 24) {
                matchup
                if !SportsCombatRules.tape(page).isEmpty { SportsCombatTape(page: page) }
                if !hidden, !page.detail.comparisons.isEmpty { SportsCombatStats(page: page) }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .focusSection()
            SportsFightCard(page: page, hidden: hidden)
                .frame(maxHeight: .infinity, alignment: .top)
                .focusSection()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var named: Bool { SportsCombatRules.named(page.game) }

    private var matchup: some View {
        let game = page.game
        let rounds = game.combat?.scheduledRounds.flatMap { [3, 5].contains($0) ? $0 : nil }
        let when = [SportsFormat.startDate(game), game.start == .distantPast ? nil : game.start.formatted(date: .omitted, time: .shortened),
                    game.venue, game.broadcasts?.joined(separator: " · ")]
            .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
        return SportsPanel(named ? String(localized: "Fighter Matchup") : String(localized: "Fight Information"),
                           note: game.combat?.cardName ?? game.title) {
            if named {
                HStack(alignment: .top, spacing: 20) {
                    fighter(game.awayTeam)
                    Text("VS").font(.callout.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 44)
                    fighter(game.homeTeam)
                }
                .sportsReadout()
                .accessibilityLabel(String(localized: "\(game.awayTeam.name) versus \(game.homeTeam.name)"))
            }
            VStack(alignment: .leading, spacing: 8) {
                if let division = game.combat?.division { Text(division).font(.headline) }
                if let rounds { Text("\(rounds) scheduled rounds").font(.caption).foregroundStyle(.secondary) }
                Text(status).font(.headline)
                if !when.isEmpty { Text(when).font(.caption).foregroundStyle(.secondary) }
                if let note = page.coverageNote { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
            .sportsReadout()
        }
    }

    private var status: String {
        if hidden { return String(localized: "Fight results and statistics hidden") }
        if page.lifecycle == .scheduled { return String(localized: "Scheduled") }
        if named { return SportsCombatRules.result(page.game, hidden: false) }
        return page.game.statusDetail.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Result not supplied")
    }

    private func fighter(_ athlete: SportsTeam) -> some View {
        VStack(spacing: 10) {
            SportsPlayerPortrait(name: athlete.name, headshot: SportsCombatRules.portrait(league: page.game.league, fighter: athlete),
                                 size: 120)
            Text(athlete.name).font(.headline).multilineTextAlignment(.center)
            if !hidden, let record = athlete.record, !record.isEmpty {
                Text("Current record · \(record)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Both fighters' height, reach, weight and stance side by side (Expo "Tale of the tape"); one
/// stop per row.
struct SportsCombatTape: View {
    let page: SportsGamePage

    var body: some View {
        SportsPanel(String(localized: "Tale of the Tape")) {
            SportsCombatNames(page: page)
            ForEach(SportsCombatRules.tape(page), id: \.label) { row in
                HStack {
                    Text(row.away ?? "—").frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.label).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    Text(row.home ?? "—").frame(maxWidth: .infinity, alignment: .trailing)
                }
                .sportsReadout()
            }
        }
    }
}

/// The fight's statistics (Expo "Fight statistics"): each row's figures around its name, with
/// bars for comparable totals (the away fighter's in the accent). One stop per row.
struct SportsCombatStats: View {
    let page: SportsGamePage

    var body: some View {
        SportsPanel(String(localized: "Fight Statistics")) {
            SportsCombatNames(page: page)
            ForEach(Array(page.detail.comparisons.enumerated()), id: \.offset) { _, row in
                VStack(spacing: 8) {
                    SportsColumns(weights: [1, 2, 1], spacing: 12) {
                        Text(row.away.isEmpty ? "—" : row.away).fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.label).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        Text(row.home.isEmpty ? "—" : row.home).fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    if let values = SportsCombatRules.barValues(label: row.label, away: row.away, home: row.home) {
                        let top = max(values.0, values.1, 1)
                        HStack(spacing: 14) {
                            bar(values.0 / top, color: SportsStatusPill.accent, alignment: .trailing)
                            bar(values.1 / top, color: .white, alignment: .leading)
                        }
                        .frame(height: 8)
                        .accessibilityHidden(true)
                    }
                }
                .monospacedDigit()
                .sportsReadout()
            }
        }
    }

    private func bar(_ share: Double, color: Color, alignment: Alignment) -> some View {
        Capsule().fill(Color.white.opacity(0.1)).overlay(alignment: alignment) {
            GeometryReader { proxy in
                Capsule().fill(color).frame(width: proxy.size.width * share).frame(maxWidth: .infinity, alignment: alignment)
            }
        }
    }
}

/// The two fighters' names over a side-by-side table (away left, home right).
private struct SportsCombatNames: View {
    let page: SportsGamePage

    var body: some View {
        HStack {
            Text(page.game.awayTeam.name).frame(maxWidth: .infinity, alignment: .leading)
            Text(page.game.homeTeam.name).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.caption).foregroundStyle(.secondary)
    }
}
