import SwiftUI

/// Which body a hub game card draws (Expo `CardBody`'s branches): tennis's set grid, a fight's
/// portraits, a field event's leaders (individual golf, a boxing card without named fighters), or
/// the team matchup.
enum SportsCardVariant: Equatable {
    case tennis, combat, field, matchup

    init(game: SportsGame, kind: SportsKind) {
        switch kind {
        case .tennis: self = .tennis
        case .golf where !game.isMatchup: self = .field
        case .boxing where !SportsCombatRules.named(game): self = .field
        case .mma, .boxing: self = .combat
        default: self = .matchup
        }
    }
}

/// A card's top line: the competition and the LIVE / FINAL state.
struct SportsCardHeading: View {
    let leagueName: String
    let lifecycle: SportsLifecycle

    var body: some View {
        HStack {
            Text(leagueName.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            SportsStatusPill(lifecycle: lifecycle)
        }
    }
}

/// The amber "Updates delayed" under a card whose league is serving older data.
struct SportsCardDelayed: View {
    var body: some View {
        Text("Updates delayed").font(.caption2).foregroundStyle(SportsStatusPill.amber)
    }
}

extension SportsTeam {
    /// A logo-less side's mark: a team's short abbreviation ("RCB"), else a player's initials
    /// ("Chris Rodesch" → "CR").
    var monogram: String {
        if let abbreviation, !abbreviation.isEmpty, abbreviation.count <= 4,
           !abbreviation.contains(" "), !abbreviation.contains(".") {
            return abbreviation
        }
        let words = name.split(whereSeparator: { $0 == " " || $0 == "/" }).filter { $0.first?.isLetter == true }
        guard let first = words.first?.first else { return String(shortName.prefix(3)) }
        let last = words.count > 1 ? words.last?.first : nil
        return [first, last].compactMap { $0 }.map(String.init).joined().uppercased()
    }
}

/// A field event on the hub (Expo `FieldEventCard` for individual golf and schedule-only boxing):
/// the event's title, how it stands, then the top two on the leaderboard with their score and
/// round ("-19 · R4"). Hide Scores keeps the title and drops the standings.
struct SportsFieldCard: View {
    let game: SportsGame
    let leagueName: String
    let kind: SportsKind
    let spoilers: Bool
    var stale = false

    /// The leaders: the detail's leaderboard when the scoreboard carries it, else the listed field.
    nonisolated static func leaders(_ game: SportsGame) -> [(id: String, name: String, value: String?)] {
        if let board = game.detail?.leaderboard, !board.isEmpty {
            return board.prefix(2).map { entry in
                let value = [entry.score, entry.latestRound.map { "R\($0)" }].compactMap { $0 }.joined(separator: " · ")
                return (entry.id, entry.name, value.isEmpty ? nil : value)
            }
        }
        return (game.participants?.items ?? []).prefix(2).map { ($0.id, $0.name, $0.score) }
    }

    var body: some View {
        let rows = spoilers || game.lifecycle == .scheduled ? [] : Self.leaders(game)
        VStack(alignment: .leading, spacing: 8) {
            SportsCardHeading(leagueName: leagueName, lifecycle: game.lifecycle)
            Text(game.displayTitle).font(.callout.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.85)
            Text(progress).font(.caption.weight(.semibold))
                .foregroundStyle(game.lifecycle == .live ? SportsStatusPill.accent : .primary).lineLimit(1)
            Spacer(minLength: 0)
            if rows.isEmpty {
                Text(empty).font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(rows, id: \.id) { row in
                HStack(spacing: 12) {
                    Text(row.name).font(.caption).lineLimit(1)
                    Spacer(minLength: 8)
                    if let value = row.value { Text(value).font(.caption.weight(.semibold)).monospacedDigit() }
                }
            }
            if stale { SportsCardDelayed() }
        }
    }

    private var progress: String {
        if game.lifecycle == .scheduled { return SportsFormat.statusLine(game, spoilers: spoilers) }
        if spoilers { return String(localized: "Results hidden") }
        return game.statusDetail.flatMap { $0.isEmpty ? nil : $0 } ?? game.lifecycle.pill.capitalized
    }

    private var empty: String {
        if spoilers, game.lifecycle != .scheduled { return String(localized: "Hide Scores is on") }
        return kind == .boxing ? String(localized: "Schedule coverage · open for details") : String(localized: "Leaderboard not yet available")
    }
}
