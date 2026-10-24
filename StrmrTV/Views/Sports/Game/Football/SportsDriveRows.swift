import SwiftUI

/// A drive's place on the field as a thin bar (Expo `DrivePosition`): the field from the side's
/// own goal to the opponent's with quarter ticks, and the drive's arrow (white and thicker for
/// the drive in progress, a dot where a score ended). Every side attacks right. Without a
/// credible path (`hasReliablePath`) only a known start shows.
struct SportsDrivePositionBar: View {
    let page: SportsGamePage
    let drive: SportsFootballDrive
    let result: SportsDriveResult
    var height: CGFloat = 32

    var body: some View {
        let team = page.team(id: drive.teamId)
        let color = team.flatMap { Color(hex: page.colorHex($0)) } ?? Color.secondary
        Canvas { context, size in
            // Points, not the drawing's units, so a narrow bar keeps legible strokes.
            let scale = size.width / SportsFieldSpace.width
            let x = { (yard: Double) in SportsFieldSpace.x(yard) * scale }
            let y = size.height / 2
            var rule = Path()
            rule.move(to: CGPoint(x: x(0), y: y))
            rule.addLine(to: CGPoint(x: x(100), y: y))
            for yard in [0.0, 25, 50, 75, 100] {
                rule.move(to: CGPoint(x: x(yard), y: y - size.height * 0.34))
                rule.addLine(to: CGPoint(x: x(yard), y: y + size.height * 0.34))
            }
            context.stroke(rule, with: .color(Color.white.opacity(0.28)), lineWidth: 1.5)
            guard let team else { return }
            let own = { (yard: Double) in x(SportsFootballYards.own(yard, for: team, in: page.game)) }
            if drive.hasReliablePath, let start = drive.knownStart, let end = drive.knownEnd {
                context.arrow(x1: own(start), x2: own(end), y: y, color: color, current: result.current, score: result.scoring,
                              width: 4, dot: 1.4)
            } else if let start = drive.knownStart {
                context.dot(x: own(start), y: y, radius: 5, fill: color, stroke: 1.5)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// A drive's result: gold with a diamond when it scored; the drive in progress in the hub's
/// live red, with its dot.
struct SportsDriveResultText: View {
    let result: SportsDriveResult

    var body: some View {
        HStack(spacing: 8) {
            if result.current { Circle().fill(SportsStatusPill.live).frame(width: 10, height: 10) }
            Text((result.scoring ? "◆ " : "") + result.text)
                .fontWeight(.semibold)
                .foregroundStyle(result.current ? SportsStatusPill.live : result.scoring ? SportsTeamColors.scoring : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// "CHI 9 → NE 40", dashes where the feed has no label.
func sportsDriveSpan(_ drive: SportsFootballDrive) -> String {
    "\(drive.startLabel.isEmpty ? "—" : drive.startLabel) → \(drive.endLabel.isEmpty ? "—" : drive.endLabel)"
}

/// A drive in the Drives tab's list (Expo `FootballDrivesTable`'s row with `DrivePosition`): its
/// number in the game, side, quarter and result, its place on the field, then start → end with
/// plays, yards and time. The side's colour runs down the edge.
struct SportsDriveListRow: View {
    let page: SportsGamePage
    let drive: SportsFootballDrive
    let number: Int
    let result: SportsDriveResult

    var body: some View {
        let team = page.team(id: drive.teamId)
        HStack(alignment: .top, spacing: 18) {
            Capsule().fill(team.flatMap { Color(hex: page.colorHex($0)) } ?? .secondary).frame(width: 5)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 14) {
                    Text("\(number)").font(.headline).monospacedDigit().frame(minWidth: 36, alignment: .leading)
                    if let team { SportsTeamLogo(team: team, size: 34) }
                    Text(team?.shortName ?? String(localized: "Team unavailable")).fontWeight(.semibold)
                    Text(drive.period.isEmpty ? "—" : drive.period).foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    SportsDriveResultText(result: result)
                }
                SportsDrivePositionBar(page: page, drive: drive, result: result, height: 26)
                HStack(spacing: 14) {
                    Text(sportsDriveSpan(drive))
                    Spacer(minLength: 12)
                    Text(drive.statsLine ?? (drive.description.isEmpty ? String(localized: "Drive statistics unavailable") : drive.description))
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                .font(.caption)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }
}

/// The Overview's latest drives (Expo `FootballRecentDrives`): the four newest, each with its
/// number in the game, side, place on the field, start and end, and result. One stop each.
struct SportsRecentDrives: View {
    let page: SportsGamePage
    let possession: SportsFootballPossession?

    static func shows(_ page: SportsGamePage) -> Bool {
        !page.detail.footballDrives.isEmpty && page.lifecycle != .scheduled
    }

    var body: some View {
        let all = page.detail.footballDrives
        SportsPanel(String(localized: "Recent Drives"),
                    note: String(localized: "Newest first · Each team attacks right, own goal to opponent goal")) {
            ForEach(Array(all.suffix(4).reversed())) { drive in
                let team = page.team(id: drive.teamId)
                let result = SportsDriveResult(drive, possession: possession)
                HStack(spacing: 16) {
                    Text("\(SportsDriveExplorer.number(of: drive, in: all))").font(.headline).lineLimit(1).fixedSize()
                        .frame(width: 44, alignment: .leading)
                    HStack(spacing: 10) {
                        if let team { SportsTeamLogo(team: team, size: 32) }
                        Text(team?.shortName ?? "—").fontWeight(.semibold).lineLimit(1)
                    }
                    .frame(width: 104, alignment: .leading)
                    SportsDrivePositionBar(page: page, drive: drive, result: result)
                    Text(sportsDriveSpan(drive)).lineLimit(1).minimumScaleFactor(0.8).frame(width: 190, alignment: .leading)
                    SportsDriveResultText(result: result).frame(width: 160, alignment: .leading)
                }
                .monospacedDigit()
                .sportsReadout()
            }
        }
    }
}
