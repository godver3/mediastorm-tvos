import SwiftUI

/// A session's entries with position, laps and timing (Expo `SportsRaceTable`): "TIME / GAP"
/// (the gap to the leader, else session time or best lap), or "BEST LAP" with each entry's
/// Q1–Q3 times in qualifying. With an F1 timing archive a row adds interval, last lap, tyre,
/// stops and sectors. Every row is a stop for the remote: selecting it picks the entry for the
/// driver card, and the expanded row lists all of its labelled statistics.
struct SportsRaceTable: View {
    let drivers: [SportsRaceDriver]
    let session: SportsRaceEvent
    let selectedID: String?
    let telemetry: [SportsF1Driver]
    let expandedID: String?
    let select: (String) -> Void

    static let positionWidth: CGFloat = 64
    static let lapsWidth: CGFloat = 80
    static let timingWidth: CGFloat = 200

    var body: some View {
        let qualifying = SportsRaceFormat.isQualifying(session)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                SportsColumnHeading(String(localized: "Pos")).frame(width: Self.positionWidth)
                SportsColumnHeading(session.riders ? String(localized: "Rider / Team") : String(localized: "Driver / Team"))
                SportsColumnHeading(String(localized: "Laps")).frame(width: Self.lapsWidth)
                SportsColumnHeading(qualifying ? String(localized: "Best lap") : String(localized: "Time / Gap"), alignment: .trailing)
                    .frame(width: Self.timingWidth)
            }
            .padding(.horizontal, 16)
            ForEach(drivers) { driver in
                let f1 = telemetry.first { $0.id == (driver.number ?? driver.id) }
                Button { select(driver.id) } label: {
                    SportsRaceRow(driver: driver, qualifying: qualifying, f1: f1, expanded: driver.id == expandedID)
                }
                .buttonStyle(SportsReadoutButtonStyle(chosen: driver.id == selectedID))
                .accessibilityIdentifier("sports-race-row-\(driver.id)")
            }
        }
    }
}

/// One entry of `SportsRaceTable`.
private struct SportsRaceRow: View {
    let driver: SportsRaceDriver
    let qualifying: Bool
    let f1: SportsF1Driver?
    let expanded: Bool

    var body: some View {
        let timing = qualifying ? driver.stat("fastestLap") : SportsRaceFormat.timing(driver)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                Text(driver.position.map(String.init) ?? "–").font(.title3.weight(.bold))
                    .foregroundStyle(driver.position == 1 ? SportsStatusPill.accent : .primary)
                    .frame(width: SportsRaceTable.positionWidth, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    (Text(driver.name).fontWeight(.semibold)
                        + Text(driver.number.map { "  #\($0)" } ?? "").foregroundStyle(.secondary))
                        .font(.callout).lineLimit(1)
                    let team = [SportsRaceDriver.filled(driver.team), driver.outcome].compactMap { $0 }.joined(separator: " · ")
                    if !team.isEmpty { Text(team).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(driver.stat("lapsCompleted") ?? "–").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: SportsRaceTable.lapsWidth, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(timing ?? "–").font(.callout).monospacedDigit().lineLimit(1)
                    if timing != nil {
                        Text((qualifying ? String(localized: "Best lap") : SportsRaceFormat.timingKind(driver)) ?? "")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: SportsRaceTable.timingWidth, alignment: .trailing)
            }
            Group {
                if qualifying { qualifyingTimes }
                if let f1, !qualifying { telemetryLines(f1) }
                if expanded { statistics }
            }
            .padding(.leading, SportsRaceTable.positionWidth)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Q1–Q3 as reported, from the session or the F1 archive; "—" where no time was set.
    @ViewBuilder private var qualifyingTimes: some View {
        let times = (1...3).map { part in
            driver.stat("qual\(part)TimeMS") ?? f1.flatMap { SportsRaceDriver.filled($0.qualifyingTimes[part - 1]) }
        }
        if times.contains(where: { $0 != nil }) {
            HStack(spacing: 28) {
                ForEach(0..<3, id: \.self) { SportsReading("Q\($0 + 1)", times[$0] ?? "—") }
                if f1?.knockedOut == true {
                    Text("Knocked out").font(.caption2).foregroundStyle(SportsStatusPill.amber)
                }
            }
        }
    }

    /// An F1 archive's line for the entry: interval, last lap, tyre, stops, state, then sectors.
    private func telemetryLines(_ f1: SportsF1Driver) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 26) {
                SportsReading("INT", f1.interval.isEmpty ? "—" : f1.interval)
                SportsReading("LAST", f1.lastLap.isEmpty ? "—" : f1.lastLap)
                if let tyre = f1.stints.last {
                    SportsReading("TYRE", tyre.compound + (tyre.age.map { " · \($0)L" } ?? ""))
                }
                if let stops = f1.pitStops { SportsReading("STOPS", "\(stops)") }
                if let state = f1.state {
                    Text(state).font(.caption2.weight(.semibold)).foregroundStyle(SportsStatusPill.amber)
                }
            }
            if f1.sectors.contains(where: { !$0.isEmpty }) {
                HStack(spacing: 26) {
                    ForEach(Array(f1.sectors.enumerated()), id: \.offset) { index, sector in
                        SportsReading("S\(index + 1)", sector.isEmpty ? "—" : sector)
                    }
                }
            }
        }
    }

    /// Every statistic the provider sent for the entry, labelled.
    private var statistics: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(driver.result ?? String(localized: "Published session details")).font(.caption2).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 20, alignment: .leading)], alignment: .leading,
                      spacing: 6) {
                ForEach(Array(driver.statistics.enumerated()), id: \.offset) { _, stat in
                    SportsReading(stat.label, stat.value)
                }
            }
        }
        .padding(.top, 4)
    }
}
