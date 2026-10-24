import Foundation

/// How one play of a drive reads (Expo `classifyFootballPlay`, `footballReplaySituation`,
/// `footballPlayResult`, `footballPlayType` and `footballPlayFieldLabel`): its kind from the
/// feed's type and type id, never guessed from the narrative; the down and distance it was run
/// on; a short result; and its net movement on the field, measured from the offense's own goal
/// (it attacks right), not a player's credited yards.
struct SportsFootballPlayInfo: Equatable {
    enum Kind: Equatable { case penalty, turnover, sack, incomplete, pass, rush, kick, other }

    let kind: Kind
    /// "3rd & 4", "1st & Goal"; nil for kickoffs, extra points and the like.
    let down: String?
    /// Where the play started ("NE 27").
    let spot: String?
    /// "7-yard completion · First down", "Incomplete pass", or the feed's type.
    let result: String
    /// "Pass", "Run", "Sack", "Field goal", "Penalty" or the feed's type.
    let type: String
    /// Start and end from the offense's own goal.
    let start: Double?
    let end: Double?

    init(_ play: SportsFootballPlay, offense: SportsTeam, game: SportsGame) {
        let kind = Self.kind(play)
        let side = [game.awayTeam, game.homeTeam].first { $0.id == play.possessionTeamId } ?? offense
        let direction: Double = side.id == game.awayTeam.id ? 1 : -1
        let yard = SportsFootballYards.isValid(play.start) ? play.start : nil
        // Kickoffs are never run on a down, whatever the feed says.
        if let number = play.down, (1...4).contains(number), let distance = play.distance, distance.isFinite, distance >= 0,
           !SportsFormat.matches("kickoff", play.type) {
            let goal = yard.map { distance >= (direction == 1 ? 100 - $0 : $0) } ?? false
            down = "\(["1st", "2nd", "3rd", "4th"][number - 1]) & \(goal ? String(localized: "Goal") : Self.number(distance))"
        } else {
            down = nil
        }
        self.kind = kind
        spot = yard.map { SportsFootballYards.label($0, in: game) }
        result = Self.result(play, kind: kind)
        type = Self.type(play.type)
        start = play.start.flatMap { SportsFootballYards.isValid($0) ? SportsFootballYards.own($0, for: offense, in: game) : nil }
        end = play.end.flatMap { SportsFootballYards.isValid($0) ? SportsFootballYards.own($0, for: offense, in: game) : nil }
    }

    /// Net movement toward the opponent's goal: "+7 YD", "−3 YD", "0 YD", "—" when unplaced.
    var movement: String {
        guard let start, let end else { return "—" }
        let yards = Int(SportsFootballYards.rounded(end - start))
        return "\(yards > 0 ? "+" : yards < 0 ? "−" : "")\(abs(yards)) YD"
    }

    /// Not a snap: kickoffs, timeouts, period ends and the two-minute warning stay off the field.
    static func isFieldPlay(_ play: SportsFootballPlay) -> Bool {
        !SportsFormat.matches("kickoff|timeout|end period|end of|two.minute warning", play.type)
    }

    static func kind(_ play: SportsFootballPlay) -> Kind {
        let type = play.type.lowercased()
        let id = play.typeId ?? ""
        if SportsFormat.matches(#"\bno play\b"#, play.description) || type.contains("penalty") { return .penalty }
        if id == "26" || SportsFormat.matches("interception|fumble", type) { return .turnover }
        if id == "7" || type.contains("sack") { return .sack }
        if id == "3" || SportsFormat.matches("incompletion|incomplete", type) { return .incomplete }
        if ["24", "67"].contains(id) || SportsFormat.matches("pass reception|passing touchdown|pass complete", type) { return .pass }
        if ["5", "68"].contains(id) || SportsFormat.matches("rush|run", type) { return .rush }
        if SportsFormat.matches("kick|punt|field goal", type) { return .kick }
        return .other
    }

    private static func result(_ play: SportsFootballPlay, kind: Kind) -> String {
        if kind == .incomplete { return String(localized: "Incomplete pass") }
        guard kind == .pass || kind == .rush else { return play.type }
        let yards = play.yards.flatMap { $0.isFinite ? $0 : nil }
        let label = yards.map { kind == .pass ? String(localized: "\(number($0))-yard completion") : String(localized: "\(number($0))-yard run") }
            ?? (kind == .pass ? String(localized: "Completed pass") : String(localized: "Run"))
        if SportsFormat.matches("touchdown", play.type) { return "\(label) · \(String(localized: "Touchdown"))" }
        if play.scoring == true { return "\(label) · \(String(localized: "Scoring play"))" }
        if let yards, let distance = play.distance, distance > 0, yards >= distance { return "\(label) · \(String(localized: "First down"))" }
        return label
    }

    private static func type(_ type: String) -> String {
        if SportsFormat.matches("^pass", type) { return String(localized: "Pass") }
        if SportsFormat.matches("^(rush|run)", type) { return String(localized: "Run") }
        if SportsFormat.matches("sack", type) { return String(localized: "Sack") }
        if SportsFormat.matches("field goal", type) { return String(localized: "Field goal") }
        if SportsFormat.matches("penalty", type) { return String(localized: "Penalty") }
        return type.isEmpty ? String(localized: "Play") : type
    }

    private static func number(_ value: Double) -> String {
        value.rounded() == value && abs(value) < 1e6 ? String(Int(value)) : String(value)
    }
}

/// Where a play lane's label sits on the field drawing (Expo `footballRibbonLabel`, in the
/// drawing's 840-wide units): inside the ribbon when it is long enough, else beside its tail,
/// else above it.
struct SportsRibbonLabel: Equatable {
    enum Anchor: Equatable { case leading, center, trailing }

    let x: Double
    let anchor: Anchor
    let inside: Bool
    let above: Bool

    init(start: Double?, end: Double?, text: String) {
        let width = Double(text.count) * 7
        guard let start, let end else {
            self.init(x: 423, anchor: .center, inside: false, above: true)
            return
        }
        let x1 = SportsFieldSpace.x(start), x2 = SportsFieldSpace.x(end)
        let sign: Double = x2 >= x1 ? 1 : -1
        if abs(x2 - x1) >= width + 24 {
            self.init(x: (x1 + x2 - sign * 8) / 2, anchor: .center, inside: true, above: false)
            return
        }
        let tail = x1 - sign * 12
        if sign > 0 ? tail - width >= 82 : tail + width <= 764 {
            self.init(x: tail, anchor: sign > 0 ? .trailing : .leading, inside: false, above: false)
        } else {
            self.init(x: max(82 + width / 2, min(764 - width / 2, (x1 + x2) / 2)), anchor: .center, inside: false, above: true)
        }
    }

    private init(x: Double, anchor: Anchor, inside: Bool, above: Bool) {
        self.x = x
        self.anchor = anchor
        self.inside = inside
        self.above = above
    }
}
