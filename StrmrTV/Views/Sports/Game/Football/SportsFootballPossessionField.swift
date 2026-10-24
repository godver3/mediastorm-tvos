import SwiftUI

/// The Overview's field (Expo `FootballPossessionField`): the offense attacking right from its
/// own end zone, the ball (blue) and the line to gain (yellow) with the yards to go shaded, and
/// the current drive's latest four plays as lanes of net movement, or the drive's arrow up to
/// the ball before its plays arrive. A break, a score, a final or old data shows as a card over
/// the turf. One stop for the remote, read out as one sentence.
struct SportsFootballPossessionField: View {
    let page: SportsGamePage
    let possession: SportsFootballPossession

    var body: some View {
        let fieldPlays = possession.plays.filter(SportsFootballPlayInfo.isFieldPlay)
        let lanes = Array(fieldPlays.suffix(4)).map { SportsFootballPlayInfo($0, offense: possession.offense, game: page.game) }
        let pause = possession.pause
        SportsPanel(nil) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    Text(pause?.title ?? String(localized: "\(possession.offense.shortName) possession →"))
                        .font(.headline).foregroundStyle(Color.accentColor)
                    Spacer(minLength: 0)
                    Text(pause.map { $0.subtitle ?? "" } ?? situationLine).font(.headline).multilineTextAlignment(.trailing)
                }
                if pause == nil, let drive = possession.currentDrive, let stats = drive.statsLine {
                    Text("\(teamName) · \(String(localized: "Current drive")) · \(stats)").font(.caption).foregroundStyle(.secondary)
                }
                SportsFootballField(left: possession.offense, right: possession.opponent,
                                    leftColor: page.colorHex(possession.offense), rightColor: page.colorHex(possession.opponent)) { context in
                    marks(&context, lanes: lanes)
                }
                Text(legend(more: fieldPlays.count > 4)).font(.caption).foregroundStyle(.secondary)
                if pause == nil, possession.currentDrive == nil {
                    Text("Waiting for current-drive details.").font(.caption).foregroundStyle(.secondary)
                } else if pause == nil, possession.plays.isEmpty {
                    Text("Individual plays not supplied yet.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .sportsReadout()
            .accessibilityLabel(spoken(lanes))
        }
    }

    private var teamName: String { possession.offense.nickname.flatMap { $0.isEmpty ? nil : $0 } ?? possession.offense.name }

    private var situationLine: String {
        [possession.situation?.downDistance, possession.situation?.fieldPosition].compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }

    private func legend(more: Bool) -> String {
        var parts = [possession.pause?.title ?? String(localized: "Current drive"), String(localized: "Blue: ball"),
                     String(localized: "Yellow: first down"), String(localized: "Yards: net field movement")]
        if more { parts.append(String(localized: "Latest four plays on field")) }
        return parts.joined(separator: " · ")
    }

    private func marks(_ context: inout GraphicsContext, lanes: [SportsFootballPlayInfo]) {
        let hex = page.colorHex(possession.offense)
        let color = Color(hex: hex) ?? .accentColor
        let arrowColor = SportsTeamColors.contrast(hex, "#075332") >= 3 ? color : Color.white
        let ink: Color = SportsTeamColors.contrast(hex, "#ffffff") >= 4.5 ? .white : .black
        if let ball = possession.ball {
            if let target = possession.target {
                let x1 = SportsFieldSpace.x(min(ball, target)), x2 = SportsFieldSpace.x(max(ball, target))
                context.fill(Path(CGRect(x: x1, y: SportsFieldSpace.top, width: x2 - x1, height: SportsFieldSpace.bottom - SportsFieldSpace.top)),
                             with: .color(Color(red: 0.79, green: 0.91, blue: 0.84).opacity(0.2)))
                context.yardLine(target, color: SportsFootballField.lineToGain, width: 2)
            }
            context.yardLine(ball, color: SportsFootballField.ball, width: 2)
        }
        if possession.pause == nil {
            for (index, lane) in lanes.enumerated() {
                let y = 105 + Double(index) * 58
                let latest = index == lanes.count - 1
                if let start = lane.start, let end = lane.end {
                    context.lane(x1: SportsFieldSpace.x(start), x2: SportsFieldSpace.x(end), y: y, halfHeight: 11, fill: color,
                                 stroke: latest ? 2.5 : 1.2)
                }
                let place = SportsRibbonLabel(start: lane.start, end: lane.end, text: lane.movement)
                let anchor: UnitPoint = place.anchor == .center ? .center : place.anchor == .trailing ? .trailing : .leading
                context.draw(Text(lane.movement).font(.system(size: 12, weight: .bold)).foregroundStyle(place.inside ? ink : .white),
                             at: CGPoint(x: place.x, y: place.above ? y - 22 : y), anchor: anchor)
            }
            if lanes.isEmpty, let drive = possession.currentDrive, let start = drive.knownStart, let ball = possession.ball {
                let own = SportsFootballYards.own(start, for: possession.offense, in: page.game)
                context.arrow(x1: SportsFieldSpace.x(own), x2: SportsFieldSpace.x(ball), y: 296, color: arrowColor, current: true, score: false)
            }
        }
        if let ball = possession.ball {
            context.dot(x: SportsFieldSpace.x(ball), y: 296, radius: 7, fill: SportsFootballField.ballDot, stroke: 2)
        }
        if let pause = possession.pause {
            let height = pause.subtitle == nil ? 60.0 : 84
            context.fill(Path(roundedRect: CGRect(x: 185, y: 142, width: 490, height: height), cornerRadius: 10),
                         with: .color(Color(red: 0.03, green: 0.07, blue: 0.09).opacity(0.9)))
            context.draw(Text(pause.title).font(.system(size: 28, weight: .bold)).foregroundStyle(.white), at: CGPoint(x: 430, y: 172))
            if let subtitle = pause.subtitle {
                context.draw(Text(subtitle).font(.system(size: 17)).foregroundStyle(Color(white: 0.9)), at: CGPoint(x: 430, y: 204))
            }
        }
    }

    /// What VoiceOver reads (Expo's readout label).
    private func spoken(_ lanes: [SportsFootballPlayInfo]) -> String {
        if let pause = possession.pause, pause.kind == .waiting {
            return [pause.title, pause.subtitle].compactMap { $0 }.joined(separator: ". ")
        }
        let opening = possession.pause.map { [$0.title, $0.subtitle].compactMap { $0 }.joined(separator: ". ") }
            ?? String(localized: "\(possession.offense.name) possession, attacks right.")
        let spot = possession.situation?.fieldPosition.isEmpty == false ? possession.situation?.fieldPosition ?? "" : String(localized: "Position unavailable")
        let plays = lanes.map { "\($0.type), \($0.movement)" }.joined(separator: ". ")
        return [opening, possession.situation?.downDistance ?? "", spot, String(localized: "Current drive only."), plays]
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}

extension SportsGamePage {
    /// The sides' readable colours as `#rrggbb` (Expo `sportsMatchupColors`).
    var colorHex: SportsTeamColors.Pair {
        SportsTeamColors.hexPair(away: game.awayTeam.color, home: game.homeTeam.color,
                                 awayAlternate: game.awayTeam.alternateColor, homeAlternate: game.homeTeam.alternateColor)
    }

    func colorHex(_ team: SportsTeam) -> String { team.id == game.homeTeam.id ? colorHex.home : colorHex.away }

    /// A side's colour for text on the page's dark panels, plain text when it would be too dark.
    func textColor(_ team: SportsTeam) -> Color {
        let hex = colorHex(team)
        return SportsTeamColors.contrast(hex, "#262628") >= 3 ? Color(hex: hex) ?? .primary : .primary
    }
}
