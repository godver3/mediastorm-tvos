import Foundation

/// A choice of the hub's Sport or League filter. `sport` is the league's sport family.
struct SportsFilterOption: Hashable, Identifiable {
    let id: String
    let label: String
    var sport: String?
}

/// What a hub card is, for the Sport and League filters: its sport family, league, and college flag.
struct SportsFilterSubject: Hashable {
    let sport: String?
    let league: String
    var college = false
}

/// The hub's Sport and League filters (Expo `SportsHubTV`'s `SPORTS`, its league list and the
/// filter predicate, with `prioritizeSportsHub`'s order): which sports and leagues can be
/// chosen, pinned sports and followed competitions first, and which cards a choice keeps.
enum SportsHubFilters {
    static let all = "all"
    static let college = "college"
    static let motorsport = SportsRaceHub.motorsport

    /// Every sport in Expo's order; only those with a league turned on are offered.
    static let sports: [(id: String, label: String)] = [
        ("american-football", String(localized: "Football")), ("basketball", String(localized: "Basketball")),
        ("baseball", String(localized: "Baseball")), ("australian-football", String(localized: "Australian Football")),
        ("lacrosse", String(localized: "Lacrosse")), ("volleyball", String(localized: "Volleyball")),
        ("field-hockey", String(localized: "Field Hockey")), ("water-polo", String(localized: "Water Polo")),
        ("softball", String(localized: "Softball")), ("golf", String(localized: "Golf")), ("cricket", String(localized: "Cricket")),
        ("boxing", String(localized: "Boxing")), ("ice-hockey", String(localized: "Hockey")), ("soccer", String(localized: "Soccer")),
        ("tennis", String(localized: "Tennis")), ("mma", String(localized: "MMA")), ("rugby-union", String(localized: "Rugby Union")),
        ("rugby-league", String(localized: "Rugby League")), (motorsport, String(localized: "Motorsport")),
        (SportsCycling.sport, String(localized: "Cycling")), (college, String(localized: "College")),
    ]

    static func sportLabel(_ id: String) -> String {
        id == all ? String(localized: "All Sports") : sports.first { $0.id == id }?.label ?? id
    }

    /// A league's sport family: the catalog's, else the feed sport's name for it.
    static func family(_ league: SportsLeague) -> String? {
        league.applicationSport.flatMap { $0.isEmpty ? nil : $0 } ?? family(sport: league.sport)
    }

    /// The Expo family for a feed sport name (football, hockey, racing, rugby…).
    static func family(sport: String?) -> String? {
        switch sport {
        case nil, "": nil
        case "football": "american-football"
        case "hockey": "ice-hockey"
        case "racing": motorsport
        case "rugby": "rugby-union"
        default: sport
        }
    }

    /// The sports with a usable league: pinned ones first in pin order, then Expo's order.
    static func sportOptions(_ leagues: some Collection<SportsLeague>, pinned: [String]) -> [SportsFilterOption] {
        let usable = leagues.filter(\.isUsable)
        var present = Set(usable.compactMap(family))
        if usable.contains(where: { $0.college == true }) { present.insert(college) }
        let offered = sports.filter { present.contains($0.id) }.map { SportsFilterOption(id: $0.id, label: $0.label) }
        let pin = { (option: SportsFilterOption) in pinned.firstIndex(of: option.id) ?? Int.max }
        return offered.enumerated().sorted { (pin($0.element), $0.offset) < (pin($1.element), $1.offset) }.map(\.element)
    }

    /// The leagues of `sport` (all sports: every one): team competitions in follow order (followed,
    /// then pinned sports, then the catalog's order), then racing series, then the cycling feed's
    /// races (by their follow id, once each).
    static func leagueOptions(_ sport: String, catalog: [SportsLeague], cyclingRaces: [SportsCyclingRace],
                              followed: [String], pinned: [String]) -> [SportsFilterOption] {
        let usable = catalog.filter(\.isUsable)
        func inSport(_ league: SportsLeague) -> Bool {
            sport == all || (sport == college ? league.college == true : family(league) == sport)
        }
        let teams = usable.enumerated()
            .filter { !$0.element.isRacing && family($0.element) != SportsCycling.sport && inSport($0.element) }
            .sorted { (rank($0.element, followed: followed, pinned: pinned), $0.offset) < (rank($1.element, followed: followed, pinned: pinned), $1.offset) }
            .map { SportsFilterOption(id: $0.element.id, label: $0.element.label, sport: family($0.element)) }
        let racing = sport == all || sport == motorsport
            ? usable.filter(\.isRacing).map { SportsFilterOption(id: $0.id, label: $0.label, sport: motorsport) } : []
        let cyclingOn = usable.contains { family($0) == SportsCycling.sport }
        let cycling = (sport == all || sport == SportsCycling.sport) && cyclingOn
            ? cyclingRaces.map { SportsFilterOption(id: $0.followID, label: $0.name, sport: SportsCycling.sport) } : []
        var seen = Set<String>()
        return (teams + racing + cycling).filter { seen.insert($0.id).inserted }
    }

    /// A competition's place in follow order (Expo `prioritizeSportsHub`).
    static func rank(_ league: SportsLeague, followed: [String], pinned: [String]) -> Int {
        if let follow = followed.firstIndex(of: league.followID) { return follow }
        if let family = family(league), let pin = pinned.firstIndex(of: family) { return followed.count + pin }
        return Int.max
    }

    /// Whether a card passes the chosen `sport` and `league` (each `all` for any).
    static func matches(_ subject: SportsFilterSubject, sport: String, league: String) -> Bool {
        let sportOK = sport == all || (sport == college ? subject.college : subject.sport == sport)
        return sportOK && (league == all || league == subject.league)
    }

    /// Whether the hub offers "Competition Details" for the choice (Expo: motorsport, cycling, or
    /// a team competition): a league's standings and games, the race weekends and championships,
    /// or the cycling calendar. A racing series chosen under All Sports opens the racing view too.
    static func hasDetails(sport: String, league: String, catalog: [String: SportsLeague]) -> Bool {
        if sport == motorsport || sport == SportsCycling.sport { return true }
        guard let chosen = catalog[league] else { return false }
        return chosen.isRacing || family(chosen) != SportsCycling.sport
    }
}
