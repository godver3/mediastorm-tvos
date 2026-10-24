import SwiftUI

/// The game's facts (Expo `EventInfo` with `SportsTeamContext` and the coverage note): venue,
/// court, format, broadcasts, the event and competition, the reported status, college
/// records, and what the feed covers for this league. Before the start, the availability
/// notice carries the venue and channels instead.
struct SportsMatchInfo: View {
    let page: SportsGamePage
    /// American football says "Game Information" (Expo `FootballInformation`).
    var title = String(localized: "Match Information")

    var body: some View {
        SportsPanel(title) {
            ForEach(Array(Self.items(page).enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    Text(item.label).font(.caption).foregroundStyle(.secondary).frame(width: 190, alignment: .leading)
                    Text(item.value)
                }
                .sportsReadout()
            }
            let context = Self.teamContext(page)
            if !context.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(context, id: \.self) { Text($0) }
                }
                .font(.caption)
                .sportsReadout()
            }
            if let note = page.coverageNote {
                Text(note).font(.caption).foregroundStyle(.secondary).sportsReadout()
            }
        }
    }

    nonisolated static func items(_ page: SportsGamePage) -> [SportsStat] {
        let game = page.game
        let inNotice = page.lifecycle == .scheduled && SportsAvailabilityNotice.applies(page)
        let rows: [(String, String?)] = [
            (String(localized: "Venue"), inNotice ? nil : game.venue),
            (String(localized: "Court"), game.courtName),
            (String(localized: "Format"), game.bestOf.flatMap { [3, 5].contains($0) ? String(localized: "Best of \($0) sets") : nil }),
            (String(localized: "Broadcast"), inNotice ? nil : game.broadcasts?.joined(separator: " · ")),
            (String(localized: "Event"), game.eventContext),
            (String(localized: "Competition"), page.detail.tournamentContext),
            (String(localized: "Status"), page.kind == .tennis || page.lifecycle == .scheduled ? nil : game.statusDetail),
        ]
        return rows.compactMap { label, value in value.flatMap { $0.isEmpty ? nil : SportsStat(label: label, value: $0) } }
    }

    nonisolated static func hasNotes(_ page: SportsGamePage) -> Bool { !teamContext(page).isEmpty || page.coverageNote != nil }

    /// College records ("MICH · 7-1 overall · 4-1 conference") and where rankings come from.
    nonisolated static func teamContext(_ page: SportsGamePage) -> [String] {
        guard page.isCollege else { return [] }
        var lines = page.teams.compactMap { team -> String? in
            let parts = [team.record.map { String(localized: "\($0) overall") },
                         team.conferenceRecord.map { String(localized: "\($0) conference") }].compactMap { $0 }
            return parts.isEmpty ? nil : ([team.shortName] + parts).joined(separator: " · ")
        }
        if page.teams.contains(where: { $0.displayRank != nil }) {
            lines.append(String(localized: "Rankings supplied by ESPN for this game"))
        }
        return lines
    }
}

/// What the feed hasn't sent, or that play is held up (Expo `SportsMatchAvailability`):
/// before the start, when it starts, where and on which channels; for a postponed, canceled
/// or delayed game, the reported status; for a game without data, which panels are missing.
/// Golf, cricket and boxing have their own coverage notes instead.
struct SportsAvailabilityNotice: View {
    let page: SportsGamePage

    nonisolated static func applies(_ page: SportsGamePage) -> Bool {
        guard ![.golf, .cricket, .boxing].contains(page.kind) else { return false }
        return page.lifecycle == .scheduled || page.lifecycle.isScheduleChange || !page.hasGameData
    }

    var body: some View {
        SportsPanel(title) {
            VStack(alignment: .leading, spacing: 12) {
                if page.lifecycle.isScheduleChange, let status = page.game.statusDetail, !status.isEmpty {
                    Text(status)
                }
                Text(message).foregroundStyle(.secondary)
                ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fact.label).font(.caption).foregroundStyle(.secondary)
                        Text(fact.value)
                    }
                    .padding(.top, 6)
                }
            }
            .sportsReadout()
        }
    }

    private var title: String {
        let match = page.kind.playsMatches
        switch page.lifecycle {
        case .scheduled: return match ? String(localized: "Before the Match") : String(localized: "Before the Game")
        case .postponed: return match ? String(localized: "Match Postponed") : String(localized: "Game Postponed")
        case .canceled: return match ? String(localized: "Match Canceled") : String(localized: "Game Canceled")
        case .delayed: return String(localized: "Play Delayed")
        case .final: return String(localized: "Final Result")
        case .live: return String(localized: "Following the Score")
        }
    }

    /// The panels this sport's feed fills when it has them.
    private var modules: String {
        switch page.kind {
        case .baseball: String(localized: "Inning scores and play history")
        case .soccer: String(localized: "Match events and statistics")
        case .football: String(localized: "Drives, plays and team statistics")
        case .hockey: String(localized: "Goal and penalty events, and team statistics")
        case .tennis: String(localized: "Set scores and serve statistics")
        default: String(localized: "Scoring, shooting and player statistics")
        }
    }

    private var message: String {
        switch page.lifecycle {
        case .scheduled: String(localized: "\(modules) will appear here when supplied by the feed.")
        case .postponed:
            String(localized: "Check the latest scheduling notice for this event. Any retained statistics describe the reported game, not live play.")
        case .canceled: String(localized: "This event is marked canceled. Any retained statistics are historical; live play is not shown.")
        case .delayed: String(localized: "Scores and statistics are retained from the last update.")
        case .final: String(localized: "\(modules) are not included in this result. The scoreboard above retains the supplied result.")
        case .live: String(localized: "\(modules) are not included in this update. The scoreboard above shows the latest supplied information.")
        }
    }

    private var facts: [SportsStat] {
        guard page.lifecycle == .scheduled else { return [] }
        let game = page.game
        let start = game.start == .distantPast ? String(localized: "Time to be announced")
            : "\(SportsFormat.startDate(game)) · \(game.start.formatted(date: .omitted, time: .shortened))"
        return [SportsStat(label: String(localized: "Start"), value: start)]
            + [(String(localized: "Venue"), game.venue), (String(localized: "Broadcasts"), game.broadcasts?.joined(separator: " · "))]
            .compactMap { label, value in value.flatMap { $0.isEmpty ? nil : SportsStat(label: label, value: $0) } }
    }
}
