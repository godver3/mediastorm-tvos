import SwiftUI

/// A card or header badge. Statuses carry an SF Symbol that artwork shows instead of the
/// text (the text stays as the accessibility label and in the details header).
struct CardBadge: Hashable {
    let text: String
    var symbol: String?

    static let comingSoon = CardBadge(text: String(localized: "Coming Soon"), symbol: "calendar.badge.clock")
    static let unreleased = CardBadge(text: String(localized: "Unreleased"), symbol: "hourglass")
    static let inTheaters = CardBadge(text: String(localized: "In Theaters"), symbol: "popcorn.fill")
    static let watched = CardBadge(text: String(localized: "Watched"), symbol: "checkmark")
}

/// "Not out yet" labels, from the backend's release availability and air dates.
enum ReleaseBadge {
    /// Window in which a not-yet-released title counts as "Coming Soon" (the server applies
    /// the same window when it derives `availability`).
    static let comingSoonWindow: TimeInterval = 30 * 24 * 3600

    /// Title-level badge from the server's `availability`; older servers send only `status`.
    static func forTitle(_ title: Title) -> CardBadge? {
        forTitle(availability: title.availability, status: title.status, releaseDate: title.releaseDate)
    }

    static func forTitle(_ item: WatchlistItem) -> CardBadge? {
        forTitle(availability: item.availability, status: item.status, releaseDate: item.releaseDate)
    }

    private static func forTitle(availability: String?, status: String?, releaseDate: String?) -> CardBadge? {
        switch availability {
        case "coming_soon": .comingSoon
        case "unreleased": .unreleased
        case "theatrical": .inTheaters
        case "released": nil
        default: forTitle(status: status, releaseDate: parseDay(releaseDate))
        }
    }

    /// Legacy badge from the backend's normalized `status`. Unreleased titles read
    /// "Coming Soon" when `releaseDate` is within the next month, else "Unreleased".
    static func forTitle(status: String?, releaseDate: Date? = nil, now: Date = .now) -> CardBadge? {
        switch status?.lowercased() {
        case "upcoming", "unreleased":
            guard let releaseDate, releaseDate.timeIntervalSince(now) <= comingSoonWindow else { return .unreleased }
            return .comingSoon
        case "theatrical":
            return .inTheaters
        default:
            return nil
        }
    }

    /// Shared: building a DateFormatter is slow, and series pages parse every episode's air day.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func parseDay(_ value: String?) -> Date? {
        guard let value, value.count >= 10 else { return nil }
        return dayFormatter.date(from: String(value.prefix(10)))
    }

    /// Episode badge when the air time is still in the future ("Airs Tomorrow").
    static func forEpisode(airDate: String?, airDateTimeUTC: String? = nil, now: Date = .now) -> String? {
        guard let airs = airTime(airDate: airDate, airDateTimeUTC: airDateTimeUTC), airs > now else { return nil }
        let calendar = Calendar.current
        if calendar.isDateInToday(airs) {
            // A date-only value has no meaningful time of day.
            return airDateTimeUTC != nil ? "Airs Today \(airs.formatted(date: .omitted, time: .shortened))" : "Airs Today"
        }
        if calendar.isDateInTomorrow(airs) { return "Airs Tomorrow" }
        let sameYear = calendar.component(.year, from: airs) == calendar.component(.year, from: now)
        return "Airs " + airs.formatted(sameYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).day().year())
    }

    static func airTime(airDate: String?, airDateTimeUTC: String?) -> Date? {
        if let exact = airDateTimeUTC, let date = try? Date(exact, strategy: .iso8601) {
            return date
        }
        // Treat a date-only air day as available from local midnight.
        return parseDay(airDate)
    }
}

/// A badge on artwork. On a poster a status shows as its symbol in a small glass disc; a
/// 16:9 card (landscape, or a poster opened on focus) has room for the text capsule.
struct ArtworkBadge: View {
    let badge: CardBadge
    var poster = true

    var body: some View {
        if poster, let symbol = badge.symbol {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Circle().fill(.black.opacity(0.65)))
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                .accessibilityLabel(badge.text)
        } else {
            BadgeLabel(text: badge.text, symbol: badge.symbol)
        }
    }
}

/// Small capsule label overlaid on artwork or shown beside metadata.
struct BadgeLabel: View {
    let text: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 8) {
            if let symbol { Image(systemName: symbol) }
            Text(text.uppercased())
        }
            .font(.caption2.weight(.bold))
            .tracking(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(.black.opacity(0.65)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
    }
}
