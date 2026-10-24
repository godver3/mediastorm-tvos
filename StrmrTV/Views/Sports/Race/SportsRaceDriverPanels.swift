import SwiftUI

/// The selected entry (Expo `SportsRaceDriverCard`): name and position, team, number and result,
/// then the figures that matter most (gap, laps behind, laps, fastest lap, pit stops, time);
/// More Details adds every other statistic the provider sent.
struct SportsRaceDriverCard: View {
    let driver: SportsRaceDriver

    @State private var expanded = false

    /// The leading figures, in order.
    static let priority = ["behindTime", "behindLaps", "lapsCompleted", "fastestLap", "pitsTaken", "totalTime"]

    var body: some View {
        let supplied = driver.statistics.filter { SportsRaceDriver.filled($0.value) != nil }
        let primary = Self.priority.flatMap { name in supplied.filter { $0.name == name } }
        let secondary = supplied.filter { !Self.priority.contains($0.name) }
        let shown = expanded ? primary + secondary : primary
        SportsPanel(nil) {
            VStack(alignment: .leading, spacing: 4) {
                Text(driver.name + (driver.position.map { " · P\($0)" } ?? "")).font(.title3.weight(.bold)).lineLimit(1)
                let line = [SportsRaceDriver.filled(driver.team), driver.number.map { "#\($0)" }, SportsRaceDriver.filled(driver.result)]
                    .compactMap { $0 }
                if !line.isEmpty { Text(line.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary) }
            }
            .sportsReadout()
            if !shown.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 24, alignment: .leading)], alignment: .leading,
                          spacing: 16) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, stat in
                        SportsFigure(label: stat.label, value: stat.value.trimmingCharacters(in: .whitespaces))
                    }
                }
            }
            if !secondary.isEmpty {
                Button(expanded ? "Fewer Details" : "More Details") { expanded.toggle() }
                    .font(.caption)
                    .padding(.top, 6)
            }
        }
    }
}

/// Two entries of the session side by side (Expo `SportsRaceComparison`): position and the gap,
/// laps, fastest lap and pit stops (Q1–Q3 in qualifying). Gaps are each to the leader. The
/// second entry is picked from a menu, which stays in place whether one is chosen or not, so
/// the remote keeps its place; Close hands focus back to it.
struct SportsRaceComparison: View {
    let drivers: [SportsRaceDriver]
    let selected: SportsRaceDriver
    let session: SportsRaceEvent

    @State private var otherID: String?
    @FocusState private var menuFocused: Bool

    private static let race = [("behindTime", String(localized: "Gap to leader")), ("behindLaps", String(localized: "Laps behind")),
                               ("lapsCompleted", String(localized: "Laps")), ("fastestLap", String(localized: "Fastest lap")),
                               ("pitsTaken", String(localized: "Pit stops"))]
    private static let qualifying = [("qual1TimeMS", "Q1"), ("qual2TimeMS", "Q2"), ("qual3TimeMS", "Q3")]

    var body: some View {
        let options = drivers.filter { $0.id != selected.id }
        let other = options.first { $0.id == otherID }
        let noun = session.riders ? String(localized: "rider") : String(localized: "driver")
        if !options.isEmpty {
            SportsPanel(String(localized: "Compare \(noun.sportsCapitalized)s")) {
                if let other {
                    VStack(alignment: .leading, spacing: 4) {
                        row(String(localized: "Statistic"), selected.name, other.name, heading: true)
                        row(String(localized: "Position"), selected.position.map { "P\($0)" } ?? "—", other.position.map { "P\($0)" } ?? "—")
                        let fields = SportsRaceFormat.isQualifying(session) ? Self.qualifying : Self.race
                        ForEach(fields, id: \.0) { name, label in
                            row(label, selected.stat(name) ?? "—", other.stat(name) ?? "—")
                        }
                    }
                    .sportsReadout()
                    Text("Same session · — means not supplied. Gaps are to the leader, not between these entries.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Choose a second \(noun) to compare with \(selected.name).").font(.callout).foregroundStyle(.secondary)
                }
                HStack(spacing: 20) {
                    Menu {
                        ForEach(options) { option in
                            Button(option.name) { otherID = option.id }
                        }
                    } label: {
                        Text(other == nil ? String(localized: "Choose a \(noun.sportsCapitalized)")
                             : String(localized: "Change \(noun.sportsCapitalized)"))
                    }
                    .focused($menuFocused)
                    .accessibilityIdentifier("sports-race-compare")
                    if other != nil {
                        Button("Close") {
                            otherID = nil
                            menuFocused = true
                        }
                    }
                }
                .font(.caption)
                .padding(.top, 6)
            }
        }
    }

    private func row(_ label: String, _ first: String, _ second: String, heading: Bool = false) -> some View {
        HStack(spacing: 16) {
            Text(label).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array([first, second].enumerated()), id: \.offset) { _, value in
                Text(value).fontWeight(heading ? .semibold : .regular).monospacedDigit().lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .font(.callout)
    }
}
