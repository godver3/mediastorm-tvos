import Foundation

/// A ranked line of a cycling card: position, name and gap (or time, or DNF…).
struct SportsCyclingCardRow: Hashable {
    let rank: Int
    let name: String
    let value: String?
}

/// Every cycling text the hub card and the stage page show (Expo `SportsHubShowcase` cycling
/// card, `SportsCyclingDetailTV` and `SportsCyclingHub`).
enum SportsCyclingFormat {
    /// The card's heading.
    static func cardLabel(_ race: SportsCyclingRace) -> String {
        race.scheduleOnly ? String(localized: "Cycling · Published schedule") : String(localized: "Cycling")
    }

    /// The card's status pill: REST DAY, CANCELED, SCHEDULE (dates only), else the lifecycle's.
    static func cardPill(_ listing: SportsCyclingListing) -> String {
        if listing.restDay { return String(localized: "REST DAY") }
        if listing.stage?.cancelled == true { return SportsLifecycle.canceled.pill }
        if listing.race.scheduleOnly { return String(localized: "SCHEDULE") }
        return listing.lifecycle.pill
    }

    /// "Rest day", the stage's name, or "Race schedule" when the day has no stage.
    static func stageTitle(_ listing: SportsCyclingListing) -> String {
        if listing.restDay { return String(localized: "Rest day") }
        if let name = listing.stage?.name, !name.isEmpty { return name }
        return String(localized: "Race schedule")
    }

    /// Under the race's name: country and class for a calendar listing, else the stage.
    static func cardSubtitle(_ listing: SportsCyclingListing) -> String {
        guard listing.race.calendarOnly else { return stageTitle(listing) }
        return [listing.race.country, listing.race.classification].compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }

    /// How the day stands: "Racing resumes Jul 14, 2026" on a rest day, a calendar listing's dates,
    /// else the stage's distance and terrain (terrain left out when the title says it), else its date.
    static func cardProgress(_ listing: SportsCyclingListing) -> String {
        if listing.restDay { return String(localized: "Racing resumes \(SportsCycling.date(listing.nextStage?.date))") }
        if listing.race.calendarOnly { return SportsCycling.dateRange(listing.race) }
        let title = stageTitle(listing).lowercased()
        let terrain = listing.stage?.terrain.flatMap { $0.isEmpty || title.contains($0.lowercased()) ? nil : $0 }
        let metadata = [listing.stage?.distance.flatMap { $0.isEmpty ? nil : $0 }, terrain].compactMap { $0 }
        return metadata.isEmpty ? SportsCycling.date(listing.stage?.date) : metadata.joined(separator: " · ")
    }

    /// The top two ranked finishers; none with Hide Scores on.
    static func cardRows(_ listing: SportsCyclingListing, spoilers: Bool) -> [SportsCyclingCardRow] {
        guard !spoilers else { return [] }
        return (listing.stage?.results.rows ?? []).filter { $0.rank != nil }.sorted { $0.rank! < $1.rank! }.prefix(2)
            .map { SportsCyclingCardRow(rank: $0.rank!, name: $0.name, value: $0.gap ?? $0.time ?? $0.result) }
    }

    /// What the card says when it lists nobody.
    static func cardEmpty(_ listing: SportsCyclingListing, spoilers: Bool) -> String {
        if listing.restDay { return String(localized: "No racing scheduled today") }
        if listing.stage?.cancelled == true { return String(localized: "Stage canceled") }
        if listing.race.scheduleOnly { return String(localized: "Start time TBC · Find streams in event details") }
        if listing.lifecycle == .scheduled { return SportsCycling.date(listing.stage?.date) }
        return spoilers ? String(localized: "Hide Scores is on") : String(localized: "Results unavailable")
    }

    /// The stage picker's line: "Stage 21 · Jul 26, 2026".
    static func stageOption(_ stage: SportsCyclingStage) -> String { "\(stage.name) · \(SportsCycling.date(stage.date))" }

    /// "Jul 26, 2026 · Thoiry → Paris · 89 km · Flat".
    static func stageLine(_ stage: SportsCyclingStage) -> String {
        [SportsCycling.date(stage.date), stage.route, stage.distance ?? "", stage.terrain ?? ""].filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// The page's state line for the shown classification.
    static func stageState(_ race: SportsCyclingRace, _ stage: SportsCyclingStage, _ classification: SportsCyclingResults?) -> String {
        if stage.cancelled { return String(localized: "Cancelled") }
        if let classification, !classification.rows.isEmpty {
            return classification.stale ? String(localized: "Saved classification") : String(localized: "Results")
        }
        if race.scheduleOnly { return String(localized: "Published schedule") }
        if stage.status == "scheduled" { return String(localized: "Scheduled") }
        return String(localized: "Classification not available")
    }

    /// The first tab: a stage race's "Stage Overview", else "Race Overview".
    static func overviewTab(_ race: SportsCyclingRace) -> String {
        race.scheduleOnly || race.oneDay || race.championship ? String(localized: "Race Overview") : String(localized: "Stage Overview")
    }

    /// The results panel's title.
    static func resultsTitle(_ race: SportsCyclingRace, overall: Bool, teams: Bool) -> String {
        if overall && !race.oneDay { return String(localized: "General Classification") }
        if race.oneDay || race.championship { return String(localized: "Race Classification") }
        return teams ? String(localized: "Team Results") : String(localized: "Stage Results")
    }

    /// When there is no classification to list: title and message (Expo's empty notice).
    static func emptyNotice(_ race: SportsCyclingRace, _ stage: SportsCyclingStage,
                            _ classification: SportsCyclingResults?) -> (title: String, message: String) {
        let race1 = race.oneDay || race.championship
        let title: String = if stage.cancelled {
            race1 ? String(localized: "Race cancelled") : String(localized: "Stage cancelled")
        } else if stage.status == "scheduled" {
            race1 ? String(localized: "Race scheduled") : String(localized: "Stage scheduled")
        } else {
            String(localized: "Classification not available")
        }
        let message: String = if stage.cancelled {
            String(localized: "The organizer reports this event as cancelled.")
        } else if race.captured {
            String(localized: "This capture does not contain the selected classification. Check the organizer for current results.")
        } else if classification?.state == "unavailable", let reason = classification?.reason, !reason.isEmpty {
            reason
        } else {
            String(localized: "The selected classification is not available in this feed.")
        }
        return (title, message)
    }

    /// A rider's second line: team, nationality, bib.
    static func riderLine(_ result: SportsCyclingResult) -> String {
        [result.team, result.nationality, result.bib.map { String(localized: "Bib \($0)") }]
            .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
    }

    /// The leaders panel's value: the winner's time, the others' gap.
    static func leaderValue(_ result: SportsCyclingResult, gapFirst: Bool) -> String? {
        gapFirst || result.rank != 1 ? result.gap ?? result.time : result.time ?? result.gap
    }

    /// "ASO race center · Retrieved Sep 9, 2026 · Provider update Aug 17, 2026".
    static func sourceLine(_ evidence: SportsCyclingEvidence?) -> String? {
        guard let evidence else { return nil }
        return [evidence.provider.isEmpty ? String(localized: "Organizer") : evidence.provider,
                String(localized: "Retrieved \(SportsCycling.date(evidence.observedAt))"),
                evidence.updatedAt.map { String(localized: "Provider update \(SportsCycling.date($0))") }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// The stage strip's state on the calendar.
    static func stripState(_ stage: SportsCyclingStage) -> String {
        if stage.cancelled { return String(localized: "Stage cancelled") }
        if stage.results.state == "available" { return String(localized: "Results available") }
        if stage.results.state == "stale" { return String(localized: "Saved results") }
        if stage.status == "scheduled" { return String(localized: "Scheduled") }
        return String(localized: "View stage coverage")
    }
}
