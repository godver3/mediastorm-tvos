import SwiftUI

/// A matchup's two team colours for bars, markers and charts, kept readable on the dark page
/// and apart from each other (Expo `sportsMatchupColors` / `readableSportsPair`): near-black
/// fills give way to the official alternate, then to grey; clashing pairs try the alternates,
/// then a contrasting fallback for the home side.
enum SportsTeamColors {
    /// Scoring drives and plays (Expo's gold).
    static let scoring = Color(red: 1, green: 0.86, blue: 0.44)

    struct Pair: Equatable {
        let away: String
        let home: String
    }

    static func pair(away: SportsTeam, home: SportsTeam) -> (away: Color, home: Color) {
        let hex = hexPair(away: away.color, home: home.color, awayAlternate: away.alternateColor, homeAlternate: home.alternateColor)
        return (Color(hex: hex.away) ?? .cyan, Color(hex: hex.home) ?? .yellow)
    }

    /// The colour of one side of the page's game.
    static func color(_ team: SportsTeam, in game: SportsGame) -> Color {
        let colors = pair(away: game.awayTeam, home: game.homeTeam)
        return team.id == game.homeTeam.id ? colors.home : colors.away
    }

    /// Hex colours (`#rrggbb`) for the two sides.
    static func hexPair(away: String?, home: String?, awayAlternate: String? = nil, homeAlternate: String? = nil) -> Pair {
        let first = visible(away, alternate: awayAlternate), second = visible(home, alternate: homeAlternate)
        if distinct(first, second) { return Pair(away: first, home: second) }
        if let alternate = usable(homeAlternate), distinct(first, alternate) { return Pair(away: first, home: alternate) }
        if let alternate = usable(awayAlternate) {
            if distinct(alternate, second) { return Pair(away: alternate, home: second) }
            if let other = usable(homeAlternate), distinct(alternate, other) { return Pair(away: alternate, home: other) }
        }
        let fallback = ["#ffc857", "#46cfff", "#ffffff", "#ff70ac", "#8bea86"]
            .filter { distinct(first, $0) }
            .max { distance(first, $0) < distance(first, $1) }
        return fallback.map { Pair(away: first, home: $0) } ?? Pair(away: "#46cfff", home: "#ffc857")
    }

    // MARK: Colour maths

    private static func normalized(_ hex: String?) -> String? {
        guard let hex else { return nil }
        let value = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "").lowercased()
        guard value.count == 6, UInt32(value, radix: 16) != nil else { return nil }
        return "#" + value
    }

    private static func visible(_ hex: String?, alternate: String?) -> String {
        let primary = normalized(hex) ?? "#00c8f0"
        if !nearBlack(primary) { return primary }
        return usable(alternate) ?? "#b7c2cd"
    }

    private static func usable(_ hex: String?) -> String? {
        normalized(hex).flatMap { nearBlack($0) ? nil : $0 }
    }

    private static func rgb(_ hex: String) -> [Double] {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return [Double((value >> 16) & 0xFF), Double((value >> 8) & 0xFF), Double(value & 0xFF)]
    }

    /// Black and near-black fills disappear into the page.
    private static func nearBlack(_ hex: String) -> Bool {
        let channels = rgb(hex)
        let high = channels.max() ?? 0, low = channels.min() ?? 0
        return high <= 48 || (high <= 80 && high - low <= 20)
    }

    private static func distance(_ a: String, _ b: String) -> Double {
        zip(rgb(a), rgb(b)).map { ($0 - $1) * ($0 - $1) }.reduce(0, +).squareRoot()
    }

    private static func luminance(_ hex: String) -> Double {
        zip(rgb(hex), [0.2126, 0.7152, 0.0722]).map { channel, weight in
            let value = channel / 255
            return (value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)) * weight
        }.reduce(0, +)
    }

    /// The WCAG contrast ratio of two `#rrggbb` colours (Expo `sportsColorContrast`): ink on end
    /// zones, arrows on the turf.
    static func contrast(_ a: String, _ b: String) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private static func hue(_ hex: String) -> Double? {
        let c = rgb(hex).map { $0 / 255 }
        let high = c.max() ?? 0, low = c.min() ?? 0, delta = high - low
        guard delta >= 0.08 else { return nil }
        let base: Double = high == c[0] ? (c[1] - c[2]) / delta : high == c[1] ? (c[2] - c[0]) / delta + 2 : (c[0] - c[1]) / delta + 4
        return (base * 60 + 360).truncatingRemainder(dividingBy: 360)
    }

    static func distinct(_ a: String, _ b: String) -> Bool {
        if distance(a, b) < 110 { return false }
        guard let x = hue(a), let y = hue(b) else { return true }
        let gap = min(abs(x - y), 360 - abs(x - y))
        return gap >= 30 || contrast(a, b) >= 2.5
    }
}
