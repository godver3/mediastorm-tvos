import SwiftUI

/// What holds focus in the Drives tab.
enum SportsDriveFocus: Hashable {
    case side(String), drive(String), field, play(String)
}

/// The chosen drive in the Drives tab: its side, quarter, span, result and figures, the field
/// with one lane per snap (the play in focus highlighted) over the drive's own arrow, then its
/// plays in order. The field is one stop for the remote; each play is one, in a list that
/// scrolls on its own so the field stays in view.
struct SportsDriveChart: View {
    let page: SportsGamePage
    let drive: SportsFootballDrive
    let number: Int
    let result: SportsDriveResult
    let focus: FocusState<SportsDriveFocus?>.Binding

    var body: some View {
        let team = page.team(id: drive.teamId) ?? page.game.awayTeam
        let opponent = team.id == page.game.awayTeam.id ? page.game.homeTeam : page.game.awayTeam
        let lanes = SportsDriveExplorer.lanes(drive.plays)
        SportsPanel(nil) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Drive \(number) · \(team.name)").font(.headline).accessibilityAddTraits(.isHeader)
                    Text(([drive.period, sportsDriveSpan(drive)] + [drive.statsLine].compactMap { $0 }).filter { !$0.isEmpty }
                        .joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength: 12)
                SportsDriveResultText(result: result).font(.headline)
            }
            HStack(alignment: .top, spacing: 22) {
                SportsFootballField(left: team, right: opponent, leftColor: page.colorHex(team), rightColor: page.colorHex(opponent)) { context in
                    marks(&context, team: team, lanes: lanes, highlighted: highlighted)
                }
                .frame(width: 600, height: 600 * SportsFieldSpace.height / SportsFieldSpace.width)
                .sportsReadout(fill: false)
                .accessibilityLabel(spoken(team: team, lanes: lanes))
                .focused(focus, equals: .field)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(legend(lanes: lanes), id: \.self) { Text($0) }
                }
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 4) {
                    if drive.plays.isEmpty {
                        Text("Plays not supplied for this drive.").foregroundStyle(.secondary).sportsReadout()
                    }
                    ForEach(drive.plays) { play in
                        SportsDrivePlayRow(page: page, play: play, info: SportsFootballPlayInfo(play, offense: team, game: page.game),
                                           color: page.textColor(team))
                            .focused(focus, equals: .play(play.id))
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: .infinity)
        }
    }

    /// The play in focus, lit on the field.
    private var highlighted: String? {
        if case .play(let id) = focus.wrappedValue { return id }
        return nil
    }

    private func legend(lanes: [SportsFootballPlay]) -> [String] {
        var lines = [String(localized: "Attacking right →"), String(localized: "Lanes: each snap"),
                     String(localized: "Arrow: whole drive"), String(localized: "Gold ring: a score")]
        let snaps = drive.plays.filter(SportsFootballPlayInfo.isFieldPlay).count
        if snaps > lanes.count, !lanes.isEmpty { lines.append(String(localized: "Latest \(lanes.count) snaps")) }
        return lines
    }

    private func marks(_ context: inout GraphicsContext, team: SportsTeam, lanes: [SportsFootballPlay], highlighted: String?) {
        let hex = page.colorHex(team)
        let color = Color(hex: hex) ?? .accentColor
        let ink: Color = SportsTeamColors.contrast(hex, "#ffffff") >= 4.5 ? .white : .black
        let own = { (yard: Double) in SportsFootballYards.own(yard, for: team, in: page.game) }
        if drive.hasReliablePath, let start = drive.knownStart, let end = drive.knownEnd {
            let arrowColor = SportsTeamColors.contrast(hex, "#075332") >= 3 ? color : Color.white
            // Under the lanes, or across the middle when the feed sent no plays.
            let y = lanes.isEmpty ? 181.0 : 304
            context.arrow(x1: SportsFieldSpace.x(own(start)), x2: SportsFieldSpace.x(own(end)), y: y, color: arrowColor,
                          current: result.current, score: result.scoring, width: lanes.isEmpty ? 5 : 3)
            if result.scoring {
                let x = SportsFieldSpace.x(own(end))
                context.stroke(Path(ellipseIn: CGRect(x: x - 11, y: y - 11, width: 22, height: 22)), with: .color(SportsTeamColors.scoring),
                               lineWidth: 2.5)
            }
        } else if lanes.isEmpty {
            context.fill(Path(roundedRect: CGRect(x: 250, y: 152, width: 346, height: 58), cornerRadius: 10),
                         with: .color(Color(red: 0.03, green: 0.07, blue: 0.09).opacity(0.9)))
            context.draw(Text("Positions not supplied").font(.system(size: 24, weight: .semibold)).foregroundStyle(.white),
                         at: CGPoint(x: 423, y: 181))
        }
        let count = lanes.count
        let spacing = count > 1 ? min(58, 196 / Double(count - 1)) : 0
        let first = count > 1 ? 80 + (196 - spacing * Double(count - 1)) / 2 : 178
        let half = count > 1 ? min(11, spacing * 0.36) : 11
        for (index, play) in lanes.enumerated() {
            guard let start = play.start, let end = play.end else { continue }
            let y = first + Double(index) * spacing
            let lit = highlighted == nil || highlighted == play.id
            var lane = context
            lane.opacity = lit ? 1 : 0.45
            lane.lane(x1: SportsFieldSpace.x(own(start)), x2: SportsFieldSpace.x(own(end)), y: y, halfHeight: half, fill: color,
                      stroke: highlighted == play.id ? 2.5 : 1)
            if highlighted == play.id || (highlighted == nil && count <= 4) {
                let info = SportsFootballPlayInfo(play, offense: team, game: page.game)
                let place = SportsRibbonLabel(start: info.start, end: info.end, text: info.movement)
                let anchor: UnitPoint = place.anchor == .center ? .center : place.anchor == .trailing ? .trailing : .leading
                // Inside a ribbon wide and tall enough, else beside its tail, else above it.
                let inside = place.inside && half >= 8
                let beside = !place.inside && !place.above
                context.draw(Text(info.movement).font(.system(size: 13, weight: .bold)).foregroundStyle(inside ? ink : .white),
                             at: CGPoint(x: place.x, y: inside || beside ? y : y - half - 9), anchor: anchor)
            }
        }
    }

    private func spoken(team: SportsTeam, lanes: [SportsFootballPlay]) -> String {
        let plays = lanes.map { play in
            let info = SportsFootballPlayInfo(play, offense: team, game: page.game)
            return "\(info.type), \(info.movement)"
        }
        return ([String(localized: "Drive \(number), \(team.name), attacking right."), sportsDriveSpan(drive), result.text] + plays)
            .joined(separator: ". ")
    }
}

/// A play of the chosen drive: when, the down and distance and the spot, the result in a few
/// words, the feed's narrative, and the net movement in the side's colour.
struct SportsDrivePlayRow: View {
    let page: SportsGamePage
    let play: SportsFootballPlay
    let info: SportsFootballPlayInfo
    let color: Color

    var body: some View {
        let scoring = play.scoring == true
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(play.period ?? "").font(.caption).foregroundStyle(.secondary)
                Text(play.clock ?? "").fontWeight(.semibold)
            }
            .frame(width: 80, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                let situation = [info.down, info.spot].compactMap { $0 }.joined(separator: " · ")
                if !situation.isEmpty { Text(situation).font(.caption).foregroundStyle(.secondary) }
                Text((scoring ? "◆ " : "") + info.result).fontWeight(.semibold)
                    .foregroundStyle(scoring ? SportsTeamColors.scoring : .primary)
                let narrative = play.description.trimmingCharacters(in: .whitespaces)
                if !narrative.isEmpty { Text(narrative).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
            }
            Spacer(minLength: 12)
            if info.start != nil, info.end != nil, SportsFootballPlayInfo.isFieldPlay(play) {
                Text(info.movement).fontWeight(.semibold).foregroundStyle(color)
            }
        }
        .monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
        .sportsReadout()
    }
}
