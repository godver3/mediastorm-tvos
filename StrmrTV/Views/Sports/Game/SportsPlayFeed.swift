import Foundation

/// The Play-by-Play tab's filters and pages (Expo `PlaysPanel`): every play or only scoring
/// ones (goals for soccer and hockey), soccer cards and substitutions, hockey penalties and
/// shots, one period, and pages of 16, newest first as the feed sends them.
struct SportsPlayFeed {
    enum Filter: String, Hashable, CaseIterable {
        case all, scoring, cards, substitutions, penalties, shots
    }

    static let pageSize = 16

    let plays: [SportsPlay]
    let kind: SportsKind
    var filter: Filter = .all
    /// nil for every period.
    var period: String?
    var page = 0

    /// The filters this sport offers.
    var filters: [Filter] {
        switch kind {
        case .soccer: [.all, .scoring, .cards, .substitutions]
        case .hockey: [.all, .scoring, .penalties, .shots]
        default: [.all, .scoring]
        }
    }

    func label(_ filter: Filter) -> String {
        let goals = kind == .soccer || kind == .hockey
        switch filter {
        case .all: return kind == .soccer ? String(localized: "All Key Events") : String(localized: "All Plays")
        case .scoring: return goals ? String(localized: "Goals") : String(localized: "Scoring Plays")
        case .cards: return String(localized: "Cards")
        case .substitutions: return String(localized: "Substitutions")
        case .penalties: return String(localized: "Penalties")
        case .shots: return String(localized: "Shots")
        }
    }

    /// The feed's periods in order of appearance; the filter shows only with two or more.
    var periods: [String] {
        var seen = Set<String>()
        return plays.map(\.periodLabel).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The chosen period while the feed still has it.
    var activePeriod: String? { period.flatMap { periods.contains($0) ? $0 : nil } }

    var visible: [SportsPlay] {
        let period = activePeriod
        return plays.filter { play in
            (period == nil || play.periodLabel == period) && matches(play)
        }
    }

    var pageCount: Int { max(1, Int((Double(visible.count) / Double(Self.pageSize)).rounded(.up))) }
    var currentPage: Int { min(max(page, 0), pageCount - 1) }

    var pagePlays: [SportsPlay] {
        let all = visible
        let start = currentPage * Self.pageSize
        return start < all.count ? Array(all[start..<min(start + Self.pageSize, all.count)]) : []
    }

    /// "Newest first · 12 plays" on one page, "Newest first · 17–32 of 180" across several.
    var summary: String {
        let count = visible.count
        if pageCount == 1 {
            let noun = kind == .soccer ? String(localized: "key events") : String(localized: "plays")
            return String(localized: "Newest first · \(count) \(noun)")
        }
        let first = currentPage * Self.pageSize + 1
        return String(localized: "Newest first · \(first)–\(min(first + Self.pageSize - 1, count)) of \(count)")
    }

    var emptyText: String {
        filter == .scoring ? String(localized: "No scoring plays in the loaded feed.") : String(localized: "No plays in the loaded feed.")
    }

    private func matches(_ play: SportsPlay) -> Bool {
        let kind = SportsEventKind(title: play.title)
        switch filter {
        case .all: return true
        case .scoring:
            return self.kind == .soccer || self.kind == .hockey ? kind == .goal || play.scoring : play.scoring
        case .cards: return kind == .yellowCard || kind == .redCard
        case .substitutions: return kind == .substitution
        case .penalties: return kind == .penalty
        case .shots:
            return kind == .goal || SportsFormat.matches(#"^(shot|shot on goal|shot on target|saved shot|missed shot|blocked shot)$"#,
                                                         play.title.trimmingCharacters(in: .whitespaces))
        }
    }
}

/// A soccer or hockey event's type from the feed's title, never from its narrative (Expo
/// `sportsTimelineKind`).
enum SportsEventKind: Equatable {
    case goal, yellowCard, redCard, substitution, penalty, other

    init(title: String) {
        let normalized = title.lowercased().trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"[_-]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if Self.goals.contains(normalized) { self = .goal }
        else if ["yellow card", "yellowcard", "booking"].contains(normalized) { self = .yellowCard }
        else if ["red card", "redcard", "second yellow card", "second yellow", "yellow red card"].contains(normalized) { self = .redCard }
        else if ["substitution", "substitution on", "substitution off", "substitutionon", "substitutionoff"].contains(normalized) {
            self = .substitution
        } else if Self.penalties.contains(normalized) { self = .penalty }
        else { self = .other }
    }

    private static let goals: Set = [
        "goal", "own goal", "goal scored", "goal header", "goal free kick", "goal volley", "goal left footed shot",
        "goal right footed shot", "penalty scored", "penalty goal", "power play goal", "short handed goal",
        "shorthanded goal", "empty net goal",
    ]

    private static let penalties: Set = [
        "penalty", "minor penalty", "major penalty", "misconduct penalty", "penalty shot", "penalty missed",
        "penalty saved", "penalty awarded", "penalty conceded",
    ]
}
