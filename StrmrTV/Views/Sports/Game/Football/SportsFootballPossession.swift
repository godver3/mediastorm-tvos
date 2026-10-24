import Foundation

/// The ball's spot and the line to gain on the feed's scale, from a live situation (Expo
/// `footballSituationGeometry`): "CHI 12" or "Midfield" placed by the side it names, then
/// "3rd & 4" or "1st & Goal" measured toward the offense's goal. Nil when the spot can't be
/// placed.
struct SportsFootballGeometry: Equatable {
    let ball: Double
    /// 1 when the away side has the ball (it attacks the home goal at 100), −1 for the home side.
    let direction: Double
    let target: Double?
    let offense: SportsTeam

    init?(situation: SportsFootballSituation, game: SportsGame) {
        guard let offense = situation.offense(in: game) else { return nil }
        let spot = situation.fieldPosition.wholeMatch(of: #/(?:Ball (?:at|on)\s+)?([\w.-]+)\s+(\d{1,2})/#.ignoresCase())
        let midfield = situation.fieldPosition.wholeMatch(of: #/midfield|50/#.ignoresCase()) != nil
        let side = spot.flatMap { match in
            [game.awayTeam, game.homeTeam].first { ($0.abbreviation ?? "").lowercased() == match.1.lowercased() }
        }
        let yards = spot.flatMap { Double($0.2) } ?? 50
        guard midfield || side != nil, yards <= 50 else { return nil }
        let ball = midfield ? 50 : side?.id == game.awayTeam.id ? yards : 100 - yards
        let direction: Double = offense.id == game.awayTeam.id ? 1 : -1
        let down = situation.downDistance
            .firstMatch(of: #/\b([1-4])(?:st|nd|rd|th)?\s*(?:&|and)\s*(goal|\d+)\b/#.ignoresCase().wordBoundaryKind(.simple))
        let distance = down.flatMap { match in
            match.2.lowercased() == "goal" ? (direction == 1 ? 100 - ball : ball) : Double(match.2)
        }
        let target = distance.map { ball + direction * $0 }
        self.ball = ball
        self.direction = direction
        self.target = target.flatMap { (0...100).contains($0) ? $0 : nil }
        self.offense = offense
    }
}

/// What holds the field still (Expo `footballPauseStatus` and `footballScoringStatus`): halftime,
/// a timeout, a score just made, or the field waiting for data.
struct SportsFootballPause: Equatable {
    enum Kind: Equatable { case halftime, timeout, score, waiting }

    let kind: Kind
    let title: String
    var subtitle: String?

    /// Halftime (with a reported "12:00 remaining"), or a timeout the status or the latest play
    /// reports, credited to a side only when exactly one is named.
    static func interval(_ page: SportsGamePage) -> SportsFootballPause? {
        let game = page.game
        let status = [game.periodLabel, game.statusDetail].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " ")
        if SportsFormat.matches("halftime|intermission", status) {
            let remaining = status.firstMatch(of: #/(?:halftime|intermission).*?(\d{1,2}:\d{2})\s*(?:remaining|left)/#.ignoresCase())
            return SportsFootballPause(kind: .halftime, title: String(localized: "Halftime"),
                                       subtitle: remaining.map { String(localized: "\(String($0.1)) remaining") })
        }
        let latest = page.detail.plays.first
        let playText = latest.map { [$0.title, $0.description ?? ""].filter { !$0.isEmpty }.joined(separator: " ") } ?? ""
        let clock = Self.clock(game)
        let timeoutPlay = SportsFormat.matches("time[ -]?out", playText) && clock != nil
            && latest?.clock == clock && latest?.periodLabel == game.periodLabel
        guard SportsFormat.matches("time[ -]?out", status) || timeoutPlay else { return nil }
        let text = "\(status) \(timeoutPlay ? playText : "")"
        let named = { (names: [String?]) in
            names.compactMap { $0?.isEmpty == false ? $0 : nil }.contains { name in
                let escaped = NSRegularExpression.escapedPattern(for: name)
                return SportsFormat.matches(#"(?:\bby\s+"# + escaped + #"\b|\b"# + escaped + #"\s+time[ -]?out\b)"#, text)
            }
        }
        let teams = [game.awayTeam, game.homeTeam]
        let exact = teams.filter { named([$0.name, $0.abbreviation]) }
        let candidates = exact.isEmpty ? teams.filter { named([$0.location, $0.nickname]) } : exact
        let caller = candidates.count == 1 ? candidates.first : nil
        let title = SportsFormat.matches("official|injury", text) ? String(localized: "Official timeout")
            : caller.map { String(localized: "Timeout · \($0.nickname.flatMap { $0.isEmpty ? nil : $0 } ?? $0.name)") }
            ?? String(localized: "Timeout")
        return SportsFootballPause(kind: .timeout, title: title)
    }

    /// The score the latest play made at this very moment of a live game ("Touchdown",
    /// "Patriots · 6 points").
    static func score(_ page: SportsGamePage, live: Bool) -> SportsFootballPause? {
        let game = page.game
        guard live, let play = page.detail.plays.first, play.scoring, let clock = play.clock,
              clock == Self.clock(game), play.periodLabel == game.periodLabel else { return nil }
        let kinds: [(String, String, Int)] = [("touchdown", String(localized: "Touchdown"), 6),
                                              ("field goal", String(localized: "Field goal"), 3),
                                              ("safety", String(localized: "Safety"), 2),
                                              ("two.point|2.point", String(localized: "Two-point conversion"), 2),
                                              ("extra point", String(localized: "Extra point"), 1)]
        guard let kind = kinds.first(where: { SportsFormat.matches($0.0, play.title) }) else { return nil }
        let (_, title, points) = kind
        let team = page.team(id: play.teamId)
        let side = team.map { $0.nickname.flatMap { $0.isEmpty ? nil : $0 } ?? $0.name }
        let worth = points == 1 ? String(localized: "1 point") : String(localized: "\(points) points")
        return SportsFootballPause(kind: .score, title: title, subtitle: [side, worth].compactMap { $0 }.joined(separator: " · "))
    }

    /// The game clock the page reads while live (Expo `detail.clock`).
    private static func clock(_ game: SportsGame) -> String? {
        game.lifecycle == .live ? game.clock.flatMap { $0.isEmpty ? nil : $0 } : nil
    }
}

/// The Overview field's state (Expo `footballPossessionView`): the offense (the side the live
/// situation names, else the away side so both end zones still show), its current drive and that
/// drive's plays, the ball and the line to gain turned to the offense's own goal, and what holds
/// the field still. A final says Final and a scheduled game "Kickoff upcoming" even when their
/// data is old (Expo shows "Updates delayed" for those too); otherwise old data waits for news.
struct SportsFootballPossession: Equatable {
    let offense: SportsTeam
    let opponent: SportsTeam
    let pause: SportsFootballPause?
    let situation: SportsFootballSituation?
    let currentDrive: SportsFootballDrive?
    let plays: [SportsFootballPlay]
    let ball: Double?
    let target: Double?
    /// Live with fresh data.
    let isLive: Bool

    init?(page: SportsGamePage, now: Date = Date()) {
        guard page.isFootballLeague else { return nil }
        let game = page.game
        let stale = page.isStale(now: now)
        let live = page.lifecycle == .live && !stale
        let situation = game.liveFootballSituation
        let known = situation?.offense(in: game)
        let offense = known ?? game.awayTeam
        let geometry = live && known != nil ? situation.flatMap { SportsFootballGeometry(situation: $0, game: game) } : nil
        let drive = live ? page.detail.footballDrives.first { $0.current && $0.teamId == offense.id } : nil
        let waiting = { (title: String, subtitle: String?) in SportsFootballPause(kind: .waiting, title: title, subtitle: subtitle) }
        switch page.lifecycle {
        case .final: pause = waiting(String(localized: "Final"), nil)
        case .scheduled: pause = waiting(String(localized: "Kickoff upcoming"), nil)
        default:
            if stale {
                pause = waiting(String(localized: "Updates delayed"), String(localized: "Waiting for the latest field position"))
            } else {
                pause = SportsFootballPause.interval(page) ?? SportsFootballPause.score(page, live: live)
                    ?? (live && known != nil ? nil : waiting(String(localized: "Waiting for field position"), nil))
            }
        }
        self.offense = offense
        opponent = offense.id == game.awayTeam.id ? game.homeTeam : game.awayTeam
        self.situation = situation
        currentDrive = drive
        plays = drive?.plays ?? []
        ball = geometry.map { SportsFootballYards.own($0.ball, for: offense, in: game) }
        target = geometry?.target.map { SportsFootballYards.own($0, for: offense, in: game) }
        isLive = live
    }
}
