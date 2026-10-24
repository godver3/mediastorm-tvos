import SwiftUI

/// Rugby wording and event rules (Expo `sports-rugby.ts`): the match state, a play's short mark,
/// and the scoring, discipline and substitution events newest first.
enum SportsRugby {
    /// "Full time", "Second half · 64'", "Half time", the start before kick-off.
    static func status(_ page: SportsGamePage) -> String {
        let game = page.game
        switch page.lifecycle {
        case .final: return String(localized: "Full time")
        case .scheduled:
            return game.start == .distantPast ? String(localized: "Scheduled") : game.start.formatted(date: .omitted, time: .shortened)
        case .live: break
        default: return page.lifecycle.pill.capitalized
        }
        if SportsFormat.matches(#"^(?:ht|half[- ]?time)$"#, game.statusDetail?.trimmingCharacters(in: .whitespaces) ?? "") {
            return String(localized: "Half time")
        }
        let period = game.periodLabel ?? ""
        let phase = phases[period] ?? period
        let text = [phase, game.clock ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        return text.isEmpty ? String(localized: "Live") : text
    }

    private static let phases = [
        "1st": String(localized: "First half"), "2nd": String(localized: "Second half"),
        "3rd": String(localized: "Extra time · first half"), "4th": String(localized: "Extra time · second half"),
    ]

    /// "Rugby union" / "Rugby league".
    static func code(_ kind: SportsKind) -> String {
        kind == .rugbyLeague ? String(localized: "Rugby league") : String(localized: "Rugby union")
    }

    /// A try, conversion, goal or card (or any scoring play): the scoring and discipline timeline.
    static func isKeyEvent(_ play: SportsPlay) -> Bool {
        play.scoring || SportsFormat.matches("try|conversion|goal|card", play.title)
    }

    static func isSubstitution(_ play: SportsPlay) -> Bool { SportsFormat.matches("substitut|replacement", play.title) }

    /// Newest first by the minute ("64'", "40+2'") when every clock is readable, else as sent.
    static func latest(_ plays: [SportsPlay]) -> [SportsPlay] {
        let minutes = plays.map(minute)
        guard minutes.allSatisfy({ $0 != nil }) else { return plays }
        return plays.enumerated().sorted { a, b in
            let x = minutes[a.offset]!, y = minutes[b.offset]!
            return x != y ? x > y : a.offset < b.offset
        }.map(\.element)
    }

    static func minute(_ play: SportsPlay) -> Int? {
        let clock = play.clock?.trimmingCharacters(in: .whitespaces) ?? ""
        guard let match = clock.firstMatch(of: /^(\d+)(?:\+(\d+))?(?:['′]|$)/) else { return nil }
        return Int(match.1)! + (match.2.flatMap { Int($0) } ?? 0)
    }

    /// The event's mark (Expo `rugbyPlaySymbol`): T, PT, C, PG, DG, FG, YC, RC, a swap for a
    /// substitution, × for a miss.
    static func mark(_ title: String) -> String {
        let text = title.lowercased()
        if SportsFormat.matches("miss|unsuccessful|disallow|no try", text) { return "×" }
        if text.contains("yellow card") { return "YC" }
        if text.contains("red card") { return "RC" }
        if SportsFormat.matches("substitut|replacement", text) { return "↔" }
        if text.contains("penalty try") { return "PT" }
        if SportsFormat.matches(#"\btry\b"#, text) { return "T" }
        if text.contains("conversion") { return "C" }
        if text.contains("penalty goal") { return "PG" }
        if text.contains("field goal") { return "FG" }
        if text.contains("drop goal") { return "DG" }
        return "•"
    }

    /// Card marks sit on the card's colour.
    static func markColor(_ mark: String) -> Color? {
        switch mark {
        case "YC": Color(red: 0.98, green: 0.75, blue: 0.14)
        case "RC": Color(red: 0.94, green: 0.27, blue: 0.27)
        default: nil
        }
    }
}
