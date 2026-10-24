import Foundation

/// The day the hub shows. Other days need a server that answers dated scoreboards.
enum SportsDay: Int, CaseIterable, Identifiable {
    case yesterday = -1, today = 0, tomorrow = 1

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .yesterday: String(localized: "Yesterday")
        case .today: String(localized: "Today")
        case .tomorrow: String(localized: "Tomorrow")
        }
    }

    /// The local day's bounds.
    var interval: DateInterval {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: rawValue, to: calendar.startOfDay(for: Date()))!
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start)!)
    }

    /// The ESPN days (US Eastern) that cover the local day: one, or two away from US time.
    var scoreboardDates: [String] {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let day = interval
        let edges = [day.start, day.end.addingTimeInterval(-1)].map { date -> String in
            let c = eastern.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }
        return edges[0] == edges[1] ? [edges[0]] : edges
    }
}

/// Which games the hub lists.
enum SportsFilter: String, CaseIterable, Identifiable {
    case all, live, upcoming, results

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: String(localized: "All")
        case .live: String(localized: "Live")
        case .upcoming: String(localized: "Upcoming")
        case .results: String(localized: "Results")
        }
    }
}

/// A row of the hub: games and race sessions together.
struct SportsSection: Identifiable {
    enum Kind: String { case live, upcoming, results, changes }
    let kind: Kind
    let items: [SportsHubItem]

    var id: String { kind.rawValue }

    var title: String {
        switch kind {
        case .live: String(localized: "Live Now")
        case .upcoming: String(localized: "Upcoming")
        case .results: String(localized: "Results")
        case .changes: String(localized: "Schedule Updates")
        }
    }
}

/// Hide scores: per device, as in the Expo app (`sports.hub.spoilerMode.v1`).
@MainActor
final class SportsSpoilers: ObservableObject {
    static let shared = SportsSpoilers()
    private static let key = "sports.spoilerMode"

    @Published var hidden = UserDefaults.standard.bool(forKey: SportsSpoilers.key) {
        didSet { UserDefaults.standard.set(hidden, forKey: Self.key) }
    }
}
