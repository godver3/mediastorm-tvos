import Foundation

/// A card badge the profile's `display.badgeVisibility` switches. Progress bars (the
/// fourth value, `watchProgress`) always show here, so they have no setting.
enum CardBadgeOption: String, CaseIterable {
    case watchState
    case releaseStatus
    case unwatchedCount
}

/// Which card badges show: this device's choices over the profile's list. Pure, for tests.
struct BadgeVisibility: Equatable {
    /// The server's default list (`["watchProgress"]`) shows none of these.
    static let serverDefault = ["watchProgress"]

    var watchState = false
    var releaseStatus = false
    var unwatchedCount = false

    /// `device` overrides each option; the rest follow `server` (the profile's list, else the
    /// server default). Matching is case- and space-insensitive, as the backend's is.
    static func resolve(device: [CardBadgeOption: Bool], server: [String]?) -> BadgeVisibility {
        let listed = Set((server ?? serverDefault).map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        func shows(_ option: CardBadgeOption) -> Bool {
            device[option] ?? listed.contains(option.rawValue.lowercased())
        }
        return BadgeVisibility(watchState: shows(.watchState), releaseStatus: shows(.releaseStatus),
                               unwatchedCount: shows(.unwatchedCount))
    }

    func shows(_ option: CardBadgeOption) -> Bool {
        switch option {
        case .watchState: watchState
        case .releaseStatus: releaseStatus
        case .unwatchedCount: unwatchedCount
        }
    }

    /// A card's top-left badges, in order: `badge` (a rank or air date always shows, a release
    /// status only with Release Status on), then the watch state with the series' unwatched
    /// episode count inside it, as the Expo card does. The count shows alone when the watch
    /// state is off or the series has none, and only when it is above zero.
    func badges(badge: CardBadge?, watch: CardBadge?, unwatchedCount count: Int?) -> [CardBadge] {
        var result: [CardBadge] = []
        if let badge, badge.kind != .release || releaseStatus { result.append(badge) }
        let shownWatch = watchState ? watch : nil
        let shownCount = unwatchedCount ? count.flatMap { $0 > 0 ? $0 : nil } : nil
        if let shownCount {
            var counted = shownWatch ?? CardBadge(text: "", kind: .watch)
            counted.count = shownCount
            result.append(counted)
        } else if let shownWatch {
            result.append(shownWatch)
        }
        return result
    }
}

/// Settings › Card Badges: this device's overrides of the profile's `display.badgeVisibility`
/// (nil follows the server), as Spoilers overrides its settings. Cards read `visibility`
/// when they draw, so a change shows at once; Home and list requests ask the server to
/// fill in missing episode counts (`includeUnwatchedCounts`) while the count shows.
@MainActor
final class BadgeSettingsStore: ObservableObject {
    static let shared = BadgeSettingsStore()

    @Published var watchState: Bool? { didSet { store(watchState, .watchState) } }
    @Published var releaseStatus: Bool? { didSet { store(releaseStatus, .releaseStatus) } }
    @Published var unwatchedCount: Bool? { didSet { store(unwatchedCount, .unwatchedCount) } }

    /// The profile's list, shown as "Default (…)". Until the server answers, the profile's
    /// last known list, so a launch doesn't flash badges in or out; nil before the first read
    /// (then the server default applies).
    @Published private(set) var server: [String]?

    private let defaults = UserDefaults.standard
    private static let serverKey = "strmrtv.badgeVisibility.server"

    private init() {
        watchState = defaults.object(forKey: Self.key(.watchState)) as? Bool
        releaseStatus = defaults.object(forKey: Self.key(.releaseStatus)) as? Bool
        unwatchedCount = defaults.object(forKey: Self.key(.unwatchedCount)) as? Bool
        server = cachedServer(for: APIClient.shared.profileID)
    }

    var visibility: BadgeVisibility {
        BadgeVisibility.resolve(device: overrides, server: server)
    }

    func shows(_ option: CardBadgeOption) -> Bool { visibility.shows(option) }

    /// The profile's value for `option` ("Default (On)").
    func serverShows(_ option: CardBadgeOption) -> Bool {
        BadgeVisibility.resolve(device: [:], server: server).shows(option)
    }

    /// Reads the profile's list; keeps the last known one when the server doesn't answer.
    func refresh() async {
        let profile = APIClient.shared.profileID
        if let fresh = await APIClient.shared.badgeVisibility() {
            guard APIClient.shared.profileID == profile else { return }
            server = fresh
            var cache = defaults.dictionary(forKey: Self.serverKey) as? [String: [String]] ?? [:]
            cache[profile] = fresh
            defaults.set(cache, forKey: Self.serverKey)
        } else if APIClient.shared.profileID == profile {
            server = cachedServer(for: profile)
        }
    }

    private var overrides: [CardBadgeOption: Bool] {
        var result: [CardBadgeOption: Bool] = [:]
        result[.watchState] = watchState
        result[.releaseStatus] = releaseStatus
        result[.unwatchedCount] = unwatchedCount
        return result
    }

    private func cachedServer(for profile: String) -> [String]? {
        (defaults.dictionary(forKey: Self.serverKey) as? [String: [String]])?[profile]
    }

    private static func key(_ option: CardBadgeOption) -> String { "strmrtv.cardBadge.\(option.rawValue)" }

    private func store(_ value: Bool?, _ option: CardBadgeOption) {
        let key = Self.key(option)
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}
