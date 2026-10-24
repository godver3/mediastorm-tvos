import SwiftUI

/// Both sides' published formations (Expo `SportsSoccerPitch` / `SoccerFormationShape`): each
/// side's crest, abbreviation and formation, then a pitch drawn natively with the home side's
/// shape attacking right and the away side's attacking left, one marker per player in the team
/// colours. These are the published shapes, never tracked positions. `summaryOnly` (the
/// Overview while play is on) keeps the formations and points to the Lineups tab for the pitch.
/// One stop for the remote.
struct SportsSoccerPitch: View {
    let page: SportsGamePage
    var summaryOnly = false

    /// Goalkeeper plus the outfield lines ("4-3-3" → [1, 4, 3, 3]) when the lines add up to ten.
    nonisolated static func rows(_ formation: String?) -> [Int]? {
        guard let formation, SportsFormat.matches(#"^\d(?:-\d){1,4}$"#, formation) else { return nil }
        let rows = formation.split(separator: "-").compactMap { Int($0) }
        guard rows.allSatisfy({ (1...5).contains($0) }), rows.reduce(0, +) == 10 else { return nil }
        return [1] + rows
    }

    private struct Side {
        let team: SportsTeam
        let formation: String?
        let rows: [Int]?
        let color: Color
    }

    private var sides: [Side] {
        let game = page.game
        let colors = SportsTeamColors.pair(away: game.awayTeam, home: game.homeTeam)
        return [(game.homeTeam, colors.home), (game.awayTeam, colors.away)].map { team, color in
            let formation = page.detail.lineups.first { $0.teamId == team.id }?.formation
            return Side(team: team, formation: formation, rows: Self.rows(formation), color: color)
        }
    }

    var body: some View {
        let sides = sides
        let available = sides.contains { $0.rows != nil }
        SportsPanel(String(localized: "Formations")) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 24) {
                    ForEach(sides, id: \.team.id) { side in
                        HStack(spacing: 14) {
                            SportsTeamLogo(team: side.team, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(side.team.shortName).font(.callout.weight(.semibold))
                                Text(side.rows == nil ? String(localized: "Not supplied") : side.formation ?? "")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if available, !summaryOnly {
                    Self.pitch(sides.map { ($0.rows ?? [], $0.color) })
                        .aspectRatio(1.65, contentMode: .fit)
                        .frame(maxHeight: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .frame(maxWidth: .infinity)
                }
                Text(!available ? String(localized: "Formations have not been supplied for this match.")
                     : summaryOnly ? String(localized: "Published formations · Full pitch in Lineups")
                     : String(localized: "Published formations · Not live player positions"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .sportsReadout()
            .accessibilityLabel(sides.map { side in
                "\(side.team.name): \(side.rows == nil ? String(localized: "formation not supplied") : side.formation ?? "")"
            }.joined(separator: ". ") + ". " + String(localized: "Published formations, not live player positions."))
        }
    }

    /// The pitch in Expo's 660 × 400 units: striped turf, touch and goal lines, halfway line and
    /// centre circle, both penalty and goal areas with their arcs and spots, the goals, then the
    /// home side's markers from the left goal and the away side's from the right.
    private static func pitch(_ sides: [(rows: [Int], color: Color)]) -> some View {
        Canvas { context, size in
            let scale = min(size.width / 660, size.height / 400)
            context.translateBy(x: (size.width - 660 * scale) / 2, y: (size.height - 400 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            let line = Color(red: 0.906, green: 0.945, blue: 0.875)
            context.fill(Path(CGRect(x: 0, y: 0, width: 660, height: 400)), with: .color(Color(red: 0.09, green: 0.24, blue: 0.19)))
            for i in 0..<10 {
                let stripe = i % 2 == 0 ? Color(red: 0.125, green: 0.286, blue: 0.204) : Color(red: 0.141, green: 0.318, blue: 0.235)
                context.fill(Path(CGRect(x: 20 + CGFloat(i) * 62, y: 20, width: 62, height: 360)), with: .color(stripe))
            }
            var lines = Path()
            lines.addRect(CGRect(x: 20, y: 20, width: 620, height: 360))
            lines.move(to: CGPoint(x: 330, y: 20))
            lines.addLine(to: CGPoint(x: 330, y: 380))
            lines.addEllipse(in: CGRect(x: 278, y: 148, width: 104, height: 104))
            for rect in [CGRect(x: 20, y: 92, width: 96, height: 216), CGRect(x: 544, y: 92, width: 96, height: 216),
                         CGRect(x: 20, y: 150, width: 34, height: 100), CGRect(x: 606, y: 150, width: 34, height: 100),
                         CGRect(x: 9, y: 177, width: 11, height: 46), CGRect(x: 640, y: 177, width: 11, height: 46)] {
                lines.addRect(rect)
            }
            // The penalty arcs: the part of each spot's 52-unit circle outside the area.
            let reach = Angle(radians: acos(31.0 / 52.0))
            lines.move(to: CGPoint(x: 116, y: 158))
            lines.addArc(center: CGPoint(x: 85, y: 200), radius: 52, startAngle: -reach, endAngle: reach, clockwise: false)
            lines.move(to: CGPoint(x: 544, y: 158))
            lines.addArc(center: CGPoint(x: 575, y: 200), radius: 52, startAngle: .degrees(180) + reach,
                         endAngle: .degrees(180) - reach, clockwise: true)
            context.stroke(lines, with: .color(line), lineWidth: 2)
            for spot in [CGPoint(x: 330, y: 200), CGPoint(x: 85, y: 200), CGPoint(x: 575, y: 200)] {
                context.fill(Path(ellipseIn: CGRect(x: spot.x - 3, y: spot.y - 3, width: 6, height: 6)), with: .color(line))
            }
            for (index, side) in sides.enumerated() {
                for (row, count) in side.rows.enumerated() {
                    let x = 44 + CGFloat(row) * 244 / CGFloat(max(1, side.rows.count - 1))
                    for i in 0..<count {
                        let center = CGPoint(x: index == 0 ? x : 660 - x, y: 20 + CGFloat(i + 1) * 360 / CGFloat(count + 1))
                        let marker = Path(ellipseIn: CGRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20))
                        context.fill(marker, with: .color(side.color))
                        context.stroke(marker, with: .color(.white), lineWidth: 2.5)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
