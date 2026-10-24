import SwiftUI

/// The Drives tab of NFL and college football games, a drive explorer (Expo `FootballDrivesTable`
/// with `DrivePosition`, plus each drive's plays): both sides or one, the drives newest first
/// with their place on the field, and beside them the chosen drive's chart and plays. The chosen
/// drive follows the remote down the list and stays marked while its plays are read; Select
/// moves on to its plays and Left comes back to it. Each column scrolls on its own, and the page
/// lifts the explorer into full view while the remote is in it.
struct SportsDrivesPanel: View {
    let page: SportsGamePage

    @Environment(\.sportsPageScroll) private var pageScroll
    @State private var teamID: String?
    @State private var chosenID: String?
    @FocusState private var focus: SportsDriveFocus?

    private static let anchor = "sports-drive-explorer"
    private static let all = "all"

    var body: some View {
        let possession = SportsFootballPossession(page: page)
        let drives = page.detail.footballDrives
        let current = drives.first { SportsDriveResult($0, possession: possession).current }
        let explorer = SportsDriveExplorer(drives: drives, teamID: teamID, chosenID: chosenID, currentID: current?.id)
        let selected = explorer.selected
        SportsColumns(weights: [1, 1.2]) {
            list(explorer, selected: selected, possession: possession)
                .containerRelativeFrame(.vertical) { length, _ in Self.height(length) }
                .focusSection()
            Group {
                if let selected {
                    SportsDriveChart(page: page, drive: selected, number: explorer.number(of: selected),
                                     result: SportsDriveResult(selected, possession: possession), focus: $focus)
                } else {
                    SportsPanel(nil) { Text("No drives supplied for this team.").foregroundStyle(.secondary).sportsReadout() }
                }
            }
            .containerRelativeFrame(.vertical) { length, _ in Self.height(length) }
            .focusSection()
            .defaultFocus($focus, .field, priority: .userInitiated)
        }
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(Self.anchor)
        .onChange(of: focus) { old, new in
            if case .drive(let id) = new { chosenID = id }
            // Coming in from the tabs, show the whole explorer (its foot at the screen's).
            if old == nil, new != nil { pageScroll?((Self.anchor, .bottom)) }
        }
    }

    /// The columns' height: the screen less the page's footer and the room the floating back
    /// button needs, so the explorer fits whole below it.
    private static func height(_ screen: CGFloat) -> CGFloat { max(520, screen - 225) }

    /// Both sides or one: chips with each side's logo and abbreviation.
    private var sides: some View {
        let chosen = teamID ?? Self.all
        let game = page.game
        return HStack(spacing: 14) {
            ForEach([nil, game.awayTeam, game.homeTeam] as [SportsTeam?], id: \.?.id) { team in
                let id = team?.id ?? Self.all
                Button { teamID = team?.id } label: {
                    if let team {
                        HStack(spacing: 10) {
                            SportsTeamLogo(team: team, size: 30)
                            Text(team.shortName)
                        }
                    } else {
                        Text("Both Teams")
                    }
                }
                .buttonStyle(FilterChipStyle(selected: chosen == id))
                .accessibilityLabel(team?.name ?? String(localized: "Both Teams"))
                .focused($focus, equals: .side(id))
            }
        }
        .font(.callout)
        .sportsChipRow()
        .defaultFocus($focus, .side(chosen), priority: .userInitiated)
    }

    private func list(_ explorer: SportsDriveExplorer, selected: SportsFootballDrive?, possession: SportsFootballPossession?) -> some View {
        let listed = explorer.listed
        return SportsPanel(String(localized: "Drives"), note: String(localized: "Newest first · \(listed.count) drives")) {
            sides
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 6) {
                    if listed.isEmpty {
                        Text("No drives supplied for this team.").foregroundStyle(.secondary).sportsReadout()
                    }
                    ForEach(listed) { drive in
                        let result = SportsDriveResult(drive, possession: possession)
                        Button { open(drive) } label: {
                            SportsDriveListRow(page: page, drive: drive, number: explorer.number(of: drive), result: result)
                        }
                        .buttonStyle(SportsReadoutButtonStyle(chosen: drive.id == selected?.id, tinted: result.current))
                        .focused($focus, equals: .drive(drive.id))
                        .accessibilityIdentifier("sports-drive-\(drive.id)")
                    }
                }
                .padding(.vertical, 6)
                .focusSection()
                .defaultFocus($focus, selected.map { .drive($0.id) }, priority: .userInitiated)
            }
            .frame(maxHeight: .infinity)
        }
    }

    /// Select on a drive: on to its plays (or its field when it has none).
    private func open(_ drive: SportsFootballDrive) {
        chosenID = drive.id
        let target: SportsDriveFocus = drive.plays.first.map { .play($0.id) } ?? .field
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            focus = target
        }
    }
}
