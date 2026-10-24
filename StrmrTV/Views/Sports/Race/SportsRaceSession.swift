import SwiftUI

/// The shown session's results (Expo `SportsRaceDetailTV`'s session view): broadcasts and the
/// snapshot line, notices for loading, late or missing data, Timing's result filter, the
/// classification (`SportsRaceTable`: eight entries on Overview with View All, every entry on
/// Timing), Timing's footnote and reported leaders, and where the figures come from. A weekend
/// without sessions says so instead.
struct SportsRaceSessionResults: View {
    @ObservedObject var model: SportsRacePageModel
    let overview: Bool
    var viewAll: () -> Void = {}

    /// The result filter chip with focus ("" is All Entries); Up and Down land on the chosen one.
    @FocusState private var filterFocus: String?

    private static let overviewRows = 8

    var body: some View {
        if let detail = model.detail {
            results(detail)
        } else if let weekend = model.weekend {
            noSessions(weekend)
        }
    }

    private func results(_ detail: SportsRaceEvent) -> some View {
        let all = detail.participants
        let entries = model.entries
        let noun = detail.riders ? String(localized: "rider") : String(localized: "driver")
        let broadcasts = detail.broadcasts.flatMap { $0.isEmpty ? nil : $0 } ?? model.weekend?.broadcasts ?? []
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                if !broadcasts.isEmpty { Text(broadcasts.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary) }
                Text(SportsRaceFormat.updateLabel(detail, delayed: model.delayed)).font(.caption).foregroundStyle(.secondary)
            }
            if model.loading && all.isEmpty {
                SportsNotice(title: String(localized: "Loading \(detail.sessionType ?? String(localized: "session"))"),
                             message: String(localized: "Checking for supplied entries and classification."), loading: true)
            }
            if model.delayed {
                SportsNotice(title: String(localized: "Updates delayed"),
                             message: all.isEmpty
                                 ? String(localized: "The latest session data could not be confirmed. No entries or classification are available in this view.")
                                 : String(localized: "Displayed results may be incomplete or from an earlier update."),
                             retry: model.retry)
            }
            if all.isEmpty && !model.loading && !model.delayed {
                let notice = SportsRaceFormat.emptyNotice(detail)
                SportsNotice(title: notice.title, message: notice.message, retry: model.retry)
            }
            if !overview && !model.resultStatuses.isEmpty { resultFilter }
            if !all.isEmpty {
                let shown = overview ? Array(entries.prefix(Self.overviewRows)) : entries
                let ranked = all.contains { $0.position != nil }
                SportsPanel(ranked ? String(localized: "Classification") : String(localized: "\(noun.sportsCapitalized) entries"),
                            note: String(localized: "\(shown.count) of \(all.count) \(noun)s")) {
                    if !ranked && !model.loading {
                        Text("Positions have not been supplied for this session.").font(.caption).foregroundStyle(.secondary)
                    }
                    SportsRaceTable(drivers: shown, session: detail, selectedID: model.competitor?.id,
                                    telemetry: telemetry, expandedID: overview ? nil : model.expandedID) { id in
                        model.competitorID = id
                        if !overview { model.expandedID = id == model.expandedID ? nil : id }
                    }
                }
                if overview && entries.count > Self.overviewRows {
                    Button("View All \(all.count) \(noun.sportsCapitalized)s", action: viewAll)
                        .accessibilityIdentifier("sports-race-view-all")
                }
                if !overview {
                    Text(SportsRaceFormat.isQualifying(detail)
                         ? String(localized: "Reported qualifying times · — means no time supplied. Elimination is shown only when reported.")
                         : String(localized: "Gap to leader when supplied; otherwise session time or best lap. Select a \(noun) for labelled statistics."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !overview && detail.isFinal && model.activeFilter == nil {
                SportsRaceLeaders(session: detail, saved: detail.stale || model.weekend?.stale == true)
            }
            Text(SportsRaceFormat.sourceLine(detail)).font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var telemetry: [SportsF1Driver] { model.timingArchive.map(SportsF1Timing.drivers) ?? [] }

    /// Timing's result filter (Expo's All entries / Classified / Retired… pills).
    private var resultFilter: some View {
        HStack(spacing: 18) {
            Button("All Entries") { model.resultFilter = nil }
                .buttonStyle(FilterChipStyle(selected: model.activeFilter == nil))
                .focused($filterFocus, equals: "")
            ForEach(model.resultStatuses, id: \.self) { status in
                Button(status) { model.resultFilter = status }
                    .buttonStyle(FilterChipStyle(selected: model.activeFilter == status))
                    .focused($filterFocus, equals: status)
            }
        }
        .font(.caption)
        .lineLimit(1)
        .sportsChipRow()
        .defaultFocus($filterFocus, model.activeFilter ?? "", priority: .userInitiated)
    }

    /// A weekend the provider lists without sessions (Expo's "Session schedule unavailable").
    private func noSessions(_ weekend: SportsRaceEvent) -> some View {
        let about = [SportsRaceFormat.date(weekend.start), SportsRaceDriver.filled(weekend.venue),
                     SportsRaceDriver.filled(weekend.statusDetail),
                     (weekend.broadcasts ?? []).isEmpty ? nil : weekend.broadcasts?.joined(separator: " · ")].compactMap { $0 }
        let title = switch SportsRaceFormat.sessionState(weekend) {
        case String(localized: "Cancelled"): String(localized: "Race weekend cancelled")
        case String(localized: "Postponed"): String(localized: "Race weekend postponed")
        default: String(localized: "Session schedule unavailable")
        }
        return VStack(alignment: .leading, spacing: 18) {
            Text(about.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
            SportsNotice(title: title, message: String(localized: "No sessions are available for this weekend. Session selection and classifications will appear when the provider supplies them."))
        }
    }
}

/// The top three as reported, with the gap or time (Expo `SportsClassificationLeaders`);
/// "Saved" when the snapshot is stale.
struct SportsRaceLeaders: View {
    let session: SportsRaceEvent
    let saved: Bool

    var body: some View {
        let leaders = session.participants.filter { (1...3).contains($0.position ?? 0) }.sorted { $0.position! < $1.position! }
        if !leaders.isEmpty {
            SportsPanel(saved ? String(localized: "Saved Session Leaders") : String(localized: "Reported Session Leaders")) {
                ForEach(leaders) { driver in
                    HStack(spacing: 20) {
                        Text("\(driver.position ?? 0)").font(.title3.weight(.bold)).foregroundStyle(SportsStatusPill.accent)
                            .frame(width: 44, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(driver.name).font(.callout.weight(.semibold)).lineLimit(1)
                            if let team = SportsRaceDriver.filled(driver.team) {
                                Text(team).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        if let time = driver.stat("behindTime") ?? driver.stat("totalTime") {
                            Text(time).font(.callout).monospacedDigit()
                        }
                    }
                    .sportsReadout()
                }
            }
        }
    }
}
