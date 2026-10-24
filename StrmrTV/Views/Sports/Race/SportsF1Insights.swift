import SwiftUI

/// Session insights from F1's timing archive (Expo `SportsF1Analysis`): weather and the selected
/// driver's last lap and interval, then Race Timeline (race-control messages; flags and safety
/// car alone on request), Tyre Stints (bars sized by each stint's laps, coloured by compound)
/// and Sectors (Q1–Q3 in qualifying). An archived or recorded snapshot, never a live feed.
struct SportsF1Insights: View {
    let archive: SportsF1Archive
    let driverNumber: String?

    private enum Tab: String, CaseIterable { case timeline, tyres, sectors }

    @State private var tab: Tab = .timeline
    @State private var flagsOnly = false
    @State private var showAll = false

    var body: some View {
        let drivers = SportsF1Timing.drivers(archive)
        let qualifying = SportsF1Timing.qualifying(archive)
        let weather = SportsF1Timing.weather(archive)
        let selected = drivers.first { $0.id == driverNumber }
        // The selected driver first, then the rest in position order.
        let ordered = selected.map { s in [s] + drivers.filter { $0.id != s.id } } ?? drivers
        SportsPanel(String(localized: "Session insights"),
                    note: archive.recorded ? String(localized: "Recorded · \(archive.capturedElapsed ?? "")") : String(localized: "Archived session")) {
            VStack(alignment: .leading, spacing: 6) {
                if !weather.isEmpty { Text(weather) }
                if let selected {
                    Text(selected.name).font(.headline)
                    Text("Selected driver · Last \(selected.lastLap.isEmpty ? "—" : selected.lastLap) · Interval \(selected.interval.isEmpty ? "—" : selected.interval)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .sportsReadout()
            HStack(spacing: 18) {
                ForEach(Tab.allCases, id: \.self) { option in
                    Button(label(option, qualifying: qualifying != nil)) { tab = option }
                        .buttonStyle(FilterChipStyle(selected: tab == option))
                }
            }
            .font(.caption)
            .lineLimit(1)
            .sportsChipRow()
            switch tab {
            case .timeline: timeline
            case .tyres: tyres(Array(ordered.prefix(5)), selected: selected)
            case .sectors: sectors(ordered, selected: selected, qualifying: qualifying)
            }
            Text("F1 timing archive · \(archive.recorded ? String(localized: "Frozen at the recorded timestamp") : String(localized: "Final session snapshot")) · No live updates")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func label(_ tab: Tab, qualifying: Bool) -> String {
        switch tab {
        case .timeline: String(localized: "Race Timeline")
        case .tyres: String(localized: "Tyre Stints")
        case .sectors: qualifying ? String(localized: "Qualifying") : String(localized: "Sectors")
        }
    }

    @ViewBuilder private var timeline: some View {
        let messages = SportsF1Timing.messages(archive).filter { !flagsOnly || !$0.flag.isEmpty || $0.category == "SafetyCar" }
        Button("Flags & Safety Car Only") { flagsOnly.toggle() }
            .buttonStyle(FilterChipStyle(selected: flagsOnly))
            .font(.caption)
        if messages.isEmpty {
            Text(flagsOnly ? "No flag messages in this capture." : "No race-control messages in this capture.")
                .font(.caption).foregroundStyle(.secondary)
        }
        ForEach(showAll ? messages : Array(messages.prefix(6))) { message in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 14) {
                    Circle().fill(Self.flagColor(message.flag)).frame(width: 12, height: 12)
                    Text((message.flag.isEmpty ? (message.category.isEmpty ? String(localized: "Race control") : message.category)
                          : message.flag).uppercased()).font(.caption2.weight(.bold))
                    if let lap = message.lap { Text("L\(lap)").font(.caption2).foregroundStyle(.secondary) }
                    if message.utc.count >= 16 {
                        Text("\(String(Array(message.utc)[11..<16])) UTC").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(message.message).font(.callout)
            }
            .sportsReadout()
        }
        if messages.count > 6 {
            Button(showAll ? "Show Recent Messages" : "View All \(messages.count) Messages") { showAll.toggle() }.font(.caption)
        }
    }

    @ViewBuilder private func tyres(_ rows: [SportsF1Driver], selected: SportsF1Driver?) -> some View {
        Text("Selected driver first · Bar segments show reported laps on each stint.").font(.caption).foregroundStyle(.secondary)
        ForEach(rows) { driver in
            VStack(alignment: .leading, spacing: 6) {
                Text((driver.abbreviation.isEmpty ? driver.name : driver.abbreviation)
                     + (driver.id == selected?.id ? " · " + String(localized: "Selected") : "")).font(.callout.weight(.semibold))
                SportsStintBar(stints: driver.stints).frame(height: 14)
                Text(driver.stints.isEmpty ? String(localized: "Stint data not supplied")
                     : driver.stints.map { "\($0.compound) · \($0.laps.map(String.init) ?? "—") laps\($0.used ? " (used set)" : "")" }
                        .joined(separator: "  /  "))
                    .font(.caption)
            }
            .sportsReadout()
        }
    }

    @ViewBuilder private func sectors(_ rows: [SportsF1Driver], selected: SportsF1Driver?, qualifying: SportsF1Qualifying?) -> some View {
        Text(qualifying.map { q in
            "Q\(q.part)" + (q.remaining.flatMap { $0 > 0 ? " · \($0) entries" : nil } ?? "")
                + " · " + String(localized: "Reported times by qualifying segment")
        } ?? String(localized: "Latest reported sector times · Not a reconstructed best lap."))
            .font(.caption).foregroundStyle(.secondary)
        ForEach(rows) { driver in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text([driver.position.map { "P\($0)" }, driver.abbreviation.isEmpty ? driver.name : driver.abbreviation,
                          driver.id == selected?.id ? String(localized: "Selected") : nil].compactMap { $0 }.joined(separator: " · "))
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text(driver.knockedOut ? String(localized: "Knocked out") : driver.bestLap.isEmpty ? "" : "Best \(driver.bestLap)")
                        .font(.caption).foregroundStyle(driver.knockedOut ? SportsStatusPill.amber : .secondary)
                }
                HStack(spacing: 30) {
                    ForEach(0..<3, id: \.self) { index in
                        let times = qualifying != nil ? driver.qualifyingTimes : driver.sectors
                        let time = index < times.count ? times[index] : ""
                        SportsReading("\(qualifying != nil ? "Q" : "S")\(index + 1)", time.isEmpty ? "—" : time)
                    }
                }
            }
            .sportsReadout()
        }
    }

    static func flagColor(_ flag: String) -> Color {
        switch flag {
        case "RED": Color(hex: "FF6370") ?? .red
        case "YELLOW": Color(hex: "F5D454") ?? .yellow
        case "GREEN": Color(hex: "65CF8E") ?? .green
        default: SportsStatusPill.accent
        }
    }
}

/// A driver's tyre stints as one bar, each segment as wide as its laps and in its compound's colour.
struct SportsStintBar: View {
    let stints: [SportsF1Stint]

    var body: some View {
        GeometryReader { proxy in
            let shown = stints.filter { ($0.laps ?? 0) > 0 }
            let total = CGFloat(shown.reduce(0) { $0 + ($1.laps ?? 0) })
            let gaps = CGFloat(max(0, shown.count - 1)) * 4
            HStack(spacing: 4) {
                ForEach(shown) { stint in
                    Capsule().fill(Self.color(stint.compound))
                        .frame(width: total > 0 ? (proxy.size.width - gaps) * CGFloat(stint.laps ?? 0) / total : 0)
                }
            }
        }
    }

    static func color(_ compound: String) -> Color {
        let hex = ["SOFT": "FF6370", "MEDIUM": "F5D454", "HARD": "DCE3E9", "INTERMEDIATE": "65CF8E", "WET": "72B9FF"][compound]
        return hex.flatMap { Color(hex: $0) } ?? Color.white.opacity(0.4)
    }
}
