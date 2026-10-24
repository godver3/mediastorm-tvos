import SwiftUI

/// A race weekend of motorsport's Competition Details (Expo's weekend card): series and state,
/// title, venue, the shown session and its winner, every session. Select opens the weekend.
struct SportsRaceWeekendRow: View {
    let weekend: SportsRaceEvent
    let seriesName: String

    var body: some View {
        let session = weekend.defaultSession
        let winner = session.flatMap { $0.isFinal ? $0.participants.first(where: \.winner) : nil }
        let entries = session?.participants.count ?? 0
        NavigationLink(value: SportsRaceRef(weekendID: weekend.id, sessionID: nil)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 18) {
                    Text(seriesName).font(.caption.weight(.bold)).foregroundStyle(SportsStatusPill.accent)
                    Text((session?.status ?? weekend.status).uppercased()).font(.caption.weight(.bold))
                        .foregroundStyle(session?.isLive == true ? SportsStatusPill.live : .secondary)
                }
                Text(SportsRaceFormat.cardTitle(weekend.title)).font(.title2.weight(.semibold)).lineLimit(2)
                if let venue = weekend.venue, !venue.isEmpty { Text(venue).font(.callout).foregroundStyle(.secondary) }
                Text("\(session?.sessionType ?? String(localized: "Session")) · \(SportsRaceFormat.date(session?.start ?? weekend.start))")
                    .font(.callout).foregroundStyle(.secondary)
                if let winner, let session {
                    let race = (session.sessionType ?? "").hasPrefix("Race")
                    Text("\(winner.name) · \(race ? String(localized: "Winner") : String(localized: "Session winner"))")
                        .font(.headline)
                }
                HStack(alignment: .top, spacing: 36) {
                    ForEach(weekend.sessions) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.sessionType ?? String(localized: "Session")).font(.caption.weight(.bold))
                                .foregroundStyle(item.isLive ? SportsStatusPill.live : SportsStatusPill.accent)
                            Text(SportsRaceFormat.date(item.start)).font(.caption).foregroundStyle(.secondary)
                            Text(item.isFinal ? String(localized: "Completed") : item.isLive ? String(localized: "Live") : String(localized: "Scheduled"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
                let count = weekend.subEvents.count
                let noun = weekend.riders ? String(localized: "riders") : String(localized: "drivers")
                Text("\(count == 1 ? String(localized: "1 session") : String(localized: "\(count) sessions")) · "
                     + (entries > 0 ? "\(entries) \(noun)" : String(localized: "View session details")))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(SportsReadoutButtonStyle())
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.06)))
        .accessibilityIdentifier("sports-weekend-\(weekend.id)")
    }
}

/// The chosen series' championship (Expo `SportsRacingHub`'s standings view): its next (or live)
/// weekend with Open Race Weekend, then the table, MotoGP's riders (`SportsMotoGPStandingsView`,
/// polled every 5 min) or the series' `/standings`; All Racing asks for a series first.
struct SportsRacingChampionship: View {
    @ObservedObject var hub: SportsHubStore
    let series: String?
    let board: SportsRaceBoard?
    let failed: Bool

    @State private var motoGP: SportsMotoGPEnrichment?
    @State private var motoGPFailed = false
    @State private var retries = 0

    var body: some View {
        if let series {
            nextWeekend(series)
            if series == "motogp" {
                SportsMotoGPStandingsView(standings: motoGP, failed: motoGPFailed) { retries += 1 }
                    .task(id: retries) { await pollMotoGP() }
            } else {
                SportsSeriesStandings(league: series).id(series)
            }
        } else {
            Text("Choose a series above to view its championship standings.").foregroundStyle(.secondary).sportsReadout()
        }
    }

    /// "CURRENT SESSION" / "NEXT ON THE CALENDAR": the live session, else the soonest upcoming one.
    private func nextWeekend(_ series: String) -> some View {
        let now = Date()
        let next = (board?.events ?? []).filter { $0.league == series }.compactMap { event -> (SportsRaceEvent, SportsRaceEvent)? in
            let candidates = ([event] + event.subEvents).filter { $0.isLive || ($0.status == "scheduled" && ($0.start ?? .distantPast) >= now) }
            return candidates.min(by: Self.sooner).map { (event, $0) }
        }.min { Self.sooner($0.1, $1.1) }
        return SportsPanel(nil) {
            VStack(alignment: .leading, spacing: 6) {
                SportsEyebrow(text: next?.1.isLive == true ? String(localized: "Current session") : String(localized: "Next on the calendar"))
                if case let (weekend, session)? = next {
                    Text(SportsRaceFormat.cardTitle(weekend.title)).font(.title3.weight(.bold))
                    Text([session.id == weekend.id ? nil : session.title, SportsRaceFormat.date(session.start)].compactMap { $0 }
                        .joined(separator: " · ")).foregroundStyle(.secondary)
                    let about = [weekend.venue, weekend.stale || failed ? String(localized: "Saved schedule · updates delayed") : nil]
                        .compactMap { $0 }.joined(separator: " · ")
                    if !about.isEmpty { Text(about).foregroundStyle(.secondary) }
                } else {
                    Text(board == nil && !failed ? "Loading the race calendar…"
                         : "No upcoming weekend supplied in the current calendar coverage.").foregroundStyle(.secondary)
                }
            }
            .sportsReadout()
            if case let (weekend, _)? = next {
                NavigationLink("Open Race Weekend", value: SportsRaceRef(weekendID: weekend.id, sessionID: nil))
                    .sportsChipRow()
            }
        }
    }

    private static func sooner(_ a: SportsRaceEvent, _ b: SportsRaceEvent) -> Bool {
        if a.isLive != b.isLive { return a.isLive }
        return (a.start ?? .distantFuture) < (b.start ?? .distantFuture)
    }

    private func pollMotoGP() async {
        while !Task.isCancelled {
            do {
                motoGP = try await APIClient.shared.sportsMotoGPStandings()
                motoGPFailed = false
            } catch {
                if error is CancellationError || Task.isCancelled { return }
                motoGPFailed = true
            }
            try? await Task.sleep(for: .seconds(300))
        }
    }
}

/// A racing series' `/standings` table, with its own model per series.
private struct SportsSeriesStandings: View {
    @StateObject private var model: SportsStandingsModel

    init(league: String) { _model = StateObject(wrappedValue: SportsStandingsModel(league: league)) }

    var body: some View { SportsLeagueStandingsView(model: model) }
}
