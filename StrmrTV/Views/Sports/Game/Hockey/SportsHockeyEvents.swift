import SwiftUI

/// A hockey play's type from the feed's title (Expo `hockeyEventKind`), never its narrative, with
/// the SF Symbol the timeline marks it with.
enum SportsHockeyEvent: Equatable {
    case goal, penalty, shot, save, blocked, missed, turnover, faceoff, hit, whistle, other

    init(_ play: SportsPlay) {
        let title = play.title.lowercased().trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"[_-]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let kinds: [String: SportsHockeyEvent] = [
            "shot": .shot, "shot on goal": .shot, "shot on target": .shot, "save": .save, "saved shot": .save,
            "blocked shot": .blocked, "blocked": .blocked, "missed shot": .missed, "missed": .missed,
            "giveaway": .turnover, "takeaway": .turnover, "faceoff": .faceoff, "face off": .faceoff, "hit": .hit, "hits": .hit,
            "stoppage": .whistle, "whistle": .whistle, "icing": .whistle, "end of period": .whistle, "period end": .whistle,
        ]
        if let kind = kinds[title] { self = kind; return }
        if play.scoring { self = .goal; return }
        switch SportsEventKind(title: play.title) {
        case .goal: self = .goal
        case .penalty: self = .penalty
        default: self = .other
        }
    }

    var symbol: String {
        switch self {
        case .goal: "hockey.puck.fill"
        case .penalty: "exclamationmark.circle"
        case .shot: "scope"
        case .save: "checkmark.shield"
        case .blocked: "hand.raised"
        case .missed: "arrow.up.forward"
        case .turnover: "arrow.left.arrow.right"
        case .faceoff: "circle.circle"
        case .hit: "burst"
        case .whistle: "pause.circle"
        case .other: "circle.fill"
        }
    }
}

/// A goal's special-teams tag from its title (Expo `hockeyGoalBadge` / `HockeyGoalBadge`): "PP ·
/// Power-play goal", "SH · Shorthanded goal", "EN · Empty-net goal"; none for shootout kicks.
struct SportsHockeyGoalBadge: Equatable {
    let short: String
    let label: String

    init?(_ play: SportsPlay) {
        guard !play.shootout else { return nil }
        let title = play.title.lowercased().trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"[_-]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        switch title {
        case "power play goal": (short, label) = ("PP", String(localized: "Power-play goal"))
        case "short handed goal", "shorthanded goal": (short, label) = ("SH", String(localized: "Shorthanded goal"))
        case "empty net goal": (short, label) = ("EN", String(localized: "Empty-net goal"))
        default: return nil
        }
    }

    var text: String { "\(short) · \(label)" }
}

/// The badge as a small accent tag (Play-by-Play rows and the timeline).
struct SportsHockeyGoalBadgeTag: View {
    let badge: SportsHockeyGoalBadge

    var body: some View {
        Text(badge.text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(SportsStatusPill.accent)
            .accessibilityLabel(badge.label)
    }
}
