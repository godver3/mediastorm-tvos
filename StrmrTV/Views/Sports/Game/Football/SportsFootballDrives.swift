import Foundation

/// Spots on an American football field (Expo `football-presentation.ts`). The feed measures
/// from the away side's goal line (0) to the home side's (100); the page draws every offense
/// attacking right, so a spot is first turned to the offense's own goal line.
enum SportsFootballYards {
    /// A spot on the field, 0 to 100 (Expo `validFootballYard`).
    static func isValid(_ yard: Double?) -> Bool {
        guard let yard else { return false }
        return yard.isFinite && yard >= 0 && yard <= 100
    }

    /// A spot measured from `team`'s own goal line (Expo `footballOwnYard`).
    static func own(_ yard: Double, for team: SportsTeam, in game: SportsGame) -> Double {
        team.id == game.homeTeam.id ? 100 - yard : yard
    }

    /// "NE 27", "CHI 12" or "50": a spot on the feed's scale named by its half of the field.
    static func label(_ yard: Double, in game: SportsGame) -> String {
        if yard == 50 { return "50" }
        let side = yard < 50 ? game.awayTeam : game.homeTeam
        return "\(side.shortName) \(Int(rounded(yard < 50 ? yard : 100 - yard)))"
    }

    /// Halves round up, as Expo's `Math.round`.
    static func rounded(_ value: Double) -> Double { (value + 0.5).rounded(.down) }
}

extension SportsFootballDrive {
    /// Where the feed placed the drive's start and end, unless it says it couldn't.
    var knownStart: Double? { startKnown == false || !SportsFootballYards.isValid(start) ? nil : start }
    var knownEnd: Double? { endKnown == false || !SportsFootballYards.isValid(end) ? nil : end }

    /// Whether the start and end make a credible path (Expo `hasReliableDrivePath`): both placed
    /// on the field and apart. Equal ends, the feed's goal-line placeholders among them, aren't
    /// movement; the drive's summary still reads.
    var hasReliablePath: Bool {
        guard let start = knownStart, let end = knownEnd else { return false }
        return start != end
    }

    /// The feed's complete, labelled summary "6 plays, 23 yards, 3:30" (Expo `footballDriveSummary`).
    var summary: SportsDriveSummary? { SportsDriveSummary(description) }

    /// Plays, net yards and time: the feed's own figures, else its summary's.
    var playsRun: Int? { playCount ?? summary?.plays }
    var netYards: Int? { yards.map { Int(SportsFootballYards.rounded($0)) } ?? summary?.yards }
    var duration: String? { elapsed ?? summary?.duration }

    /// "12 plays · 51 yards · 4:48", from what the feed sent.
    var statsLine: String? {
        let parts = [playsRun.map { $0 == 1 ? String(localized: "1 play") : String(localized: "\($0) plays") },
                     netYards.map { abs($0) == 1 ? String(localized: "\($0) yard") : String(localized: "\($0) yards") },
                     duration]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A drive's plays, yards and time read from its description; nil for any other wording, which
/// is shown as sent.
struct SportsDriveSummary: Equatable {
    let plays: Int
    let yards: Int
    let duration: String

    init?(_ description: String) {
        let text = description.trimmingCharacters(in: .whitespaces)
        guard let match = text.wholeMatch(of: #/(\d+) plays?,\s*(-?\d+) yards?,\s*(\d+:\d{2})/#.ignoresCase()),
              let plays = Int(match.1), let yards = Int(match.2) else { return nil }
        self.plays = plays
        self.yards = yards
        duration = String(match.3)
    }
}

/// How a drive ended, in words (Expo `footballDriveResult`): "In progress" for the offense's
/// drive while the game is live with fresh data (not at halftime), "Touchdown" and "Field goal"
/// for TD and FG, else the feed's own ("PUNT", "DOWNS"). Touchdowns, field goals and safeties
/// score.
struct SportsDriveResult: Equatable {
    let text: String
    let scoring: Bool
    let current: Bool

    init(_ drive: SportsFootballDrive, possession: SportsFootballPossession?) {
        let current = drive.current && possession.map { $0.isLive && $0.pause?.kind != .halftime && $0.offense.id == drive.teamId } == true
        let raw = drive.result.trimmingCharacters(in: .whitespaces)
        self.current = current
        scoring = !current && SportsFormat.matches(#"^(touchdown|td|field goal|fg|safety)$"#, raw)
        text = current ? String(localized: "In progress")
            : ["TD": String(localized: "Touchdown"), "FG": String(localized: "Field goal")][raw.uppercased()]
            ?? (raw.isEmpty ? String(localized: "Result unavailable") : raw)
    }
}
