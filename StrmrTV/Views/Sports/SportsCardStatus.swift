import Foundation

/// A live hub card's context line (Expo `MatchFooter` and `BaseballFooter`): MLB's runners with
/// the count and outs, NFL and college football's down and distance with the ball's spot, a
/// basketball or hockey situation when the feed sends one, else the reported status when it
/// names one (a power play, the bonus). None before or after the game, or with scores hidden.
struct SportsCardFooter: Equatable {
    /// An SF Symbol for the sport.
    var symbol: String?
    /// First, second and third for MLB's bases glyph.
    var bases: [Bool]?
    var text: String

    static func make(_ game: SportsGame, kind: SportsKind, spoilers: Bool) -> SportsCardFooter? {
        guard !spoilers, game.lifecycle == .live else { return nil }
        if game.league == "mlb" { return baseball(game) }
        if let football = game.liveFootballSituation {
            let text = [football.offense(in: game)?.shortName, football.downDistance.isEmpty ? nil : football.downDistance,
                        football.ballAt].compactMap { $0 }
            if !text.isEmpty { return SportsCardFooter(symbol: "football.fill", text: text.joined(separator: " · ")) }
        }
        if let hockey = game.liveHockeySituation, !hockey.strength.isEmpty {
            return SportsCardFooter(symbol: "hockey.puck.fill", text: hockey.strength)
        }
        if let basketball = game.liveBasketballSituation {
            let side = game.side(named: basketball.possession)?.shortName ?? basketball.possession
            let text = [side.isEmpty ? nil : String(localized: "\(side) possession"), basketball.bonus].compactMap { $0 }
            if !text.isEmpty { return SportsCardFooter(symbol: "basketball.fill", text: text.joined(separator: " · ")) }
        }
        return reported(game, kind: kind)
    }

    /// Expo `BaseballFooter`: hidden between half-innings and during breaks or delays.
    private static func baseball(_ game: SportsGame) -> SportsCardFooter? {
        guard let situation = game.liveBaseballSituation else { return nil }
        let phase = "\(game.periodLabel ?? "") \(game.statusDetail ?? "") \(situation.inning)"
        guard !SportsFormat.matches(#"middle|mid\b|end\b|delay|suspend|final|break"#, phase) else { return nil }
        var parts: [String] = []
        if let balls = situation.balls, let strikes = situation.strikes { parts.append(String(localized: "\(balls)–\(strikes) count")) }
        if let outs = situation.outs { parts.append(SportsBaseballState.outs(outs)) }
        let bases = situation.occupiedBases
        guard bases != nil || !parts.isEmpty else { return nil }
        return SportsCardFooter(bases: bases, text: parts.joined(separator: " · "))
    }

    /// The status text when it carries a situation and isn't just the clock (Expo `MatchFooter`).
    private static func reported(_ game: SportsGame, kind: SportsKind) -> SportsCardFooter? {
        guard let detail = game.statusDetail?.trimmingCharacters(in: .whitespaces), !detail.isEmpty else { return nil }
        let pattern = #"possession|ball|[1-4](?:st|nd|rd|th)\s*(?:&|and)|power play|bonus|shot clock|penalty|red card"#
        let status = [game.periodLabel, game.clock].compactMap { $0?.isEmpty == false ? $0 : nil }
        guard SportsFormat.matches(pattern, detail), detail != status.joined(separator: " · "),
              detail != status.joined(separator: " "), detail != game.periodLabel, detail != game.clock else { return nil }
        let symbol = switch kind {
        case .football: "football.fill"
        case .basketball: "basketball.fill"
        case .hockey: "hockey.puck.fill"
        case .soccer: "soccerball"
        default: "trophy"
        }
        return SportsCardFooter(symbol: symbol, text: detail)
    }
}

/// The card's score-change cue (Expo `useSportsScoreChange` / `SportsCardFrame`): a live card's
/// two scores while they show. A change between refreshes, never the first load and never with
/// scores hidden, lights the card for two seconds.
enum SportsScoreChange {
    static let duration: Duration = .seconds(2)

    static func key(_ game: SportsGame, spoilers: Bool) -> String? {
        guard !spoilers, game.lifecycle == .live else { return nil }
        return "\(game.awayTeam.score ?? "")|\(game.homeTeam.score ?? "")"
    }

    static func changed(from old: String?, to new: String?) -> Bool {
        guard let old, let new else { return false }
        return old != new
    }
}

extension SportsFormat {
    /// Expo `sportsCardCountdown`: never "live" on the clock alone.
    static func countdown(to start: Date?, now: Date) -> String {
        guard let start, start != .distantPast else { return String(localized: "Upcoming") }
        let seconds = start.timeIntervalSince(now)
        if seconds <= 0 { return String(localized: "Awaiting start") }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return String(localized: "Starts in \(minutes) min") }
        if minutes < 1440 {
            let hours = minutes / 60, rest = minutes % 60
            return rest == 0 ? String(localized: "Starts in \(hours)h") : String(localized: "Starts in \(hours)h \(rest)m")
        }
        let days = Int((Double(minutes) / 1440).rounded(.up))
        return days == 1 ? String(localized: "Starts in 1 day") : String(localized: "Starts in \(days) days")
    }
}
