import SwiftUI

/// The NHL's shot attempts on a rink drawn natively (Expo `SportsExtendedOverview`, "Shot attempts"):
/// the boards, centre red line, blue lines, goal lines and creases, faceoff circles, then every
/// attempt in the provider's coordinates (feet, 200 × 85 around centre ice; the teams change ends
/// each period): the away side cyan, the home side gold, goals larger with a white ring. One stop
/// for the remote; nothing without attempts on the rink.
struct SportsHockeyShotMap: View {
    let page: SportsGamePage

    static let away = Color(red: 0, green: 0.784, blue: 0.941)
    static let home = Color(red: 1, green: 0.831, blue: 0.471)
    private static let unknown = Color(red: 0.667, green: 0.702, blue: 0.741)

    /// Attempts on the rink (Expo keeps |x| ≤ 100, |y| ≤ 42.5).
    static func shots(_ page: SportsGamePage) -> [SportsHockeyShot] {
        guard page.game.league == "nhl" else { return [] }
        return page.detail.shots.filter { $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 100 && abs($0.y) <= 42.5 }
    }

    var body: some View {
        let shots = Self.shots(page)
        let game = page.game
        SportsPanel(String(localized: "Shot Attempts"),
                    note: String(localized: "Includes saved, missed and blocked attempts · Provider coordinates; teams change ends")) {
            VStack(alignment: .leading, spacing: 14) {
                rink(shots)
                HStack(spacing: 26) {
                    key(game.awayTeam, color: Self.away, count: shots.filter { $0.teamId == game.awayTeam.id }.count)
                    key(game.homeTeam, color: Self.home, count: shots.filter { $0.teamId == game.homeTeam.id }.count)
                    HStack(spacing: 8) {
                        Circle().fill(Color.secondary).overlay(Circle().strokeBorder(.white, lineWidth: 2)).frame(width: 16, height: 16)
                        Text("Goal")
                    }
                }
                .font(.caption)
            }
            .sportsReadout()
            .accessibilityLabel(String(localized: "Shot attempts map, \(game.awayTeam.name) cyan, \(game.homeTeam.name) gold, goals outlined"))
        }
    }

    private func key(_ team: SportsTeam, color: Color, count: Int) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 14, height: 14)
            SportsTeamLogo(team: team, size: 30)
            Text("\(team.shortName) · \(count)").monospacedDigit()
        }
    }

    private func rink(_ shots: [SportsHockeyShot]) -> some View {
        let game = page.game
        return Canvas { context, size in
            let scale = size.width / 208
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: 104, y: 47)
            let boards = Path(roundedRect: CGRect(x: -100, y: -42.5, width: 200, height: 85), cornerRadius: 20)
            context.fill(boards, with: .color(Color(red: 0.125, green: 0.169, blue: 0.212)))
            let red = Color(red: 0.64, green: 0.42, blue: 0.45), blue = Color(red: 0.28, green: 0.41, blue: 0.55)
            let faint = Color(red: 0.4, green: 0.47, blue: 0.54)
            var clipped = context
            clipped.clip(to: boards)
            func vertical(_ x: Double, _ color: Color, _ width: Double) {
                clipped.stroke(Path { $0.move(to: CGPoint(x: x, y: -42.5)); $0.addLine(to: CGPoint(x: x, y: 42.5)) },
                               with: .color(color), lineWidth: width)
            }
            vertical(0, red, 0.8)
            vertical(-25, blue, 1)
            vertical(25, blue, 1)
            vertical(-89, red, 0.5)
            vertical(89, red, 0.5)
            for x in [-89.0, 89] {
                let side = x < 0 ? 1.0 : -1.0
                clipped.fill(Path { path in
                    path.move(to: CGPoint(x: x, y: -4))
                    path.addArc(center: CGPoint(x: x, y: 0), radius: 6, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: side > 0)
                    path.closeSubpath()
                }, with: .color(Color(red: 0.3, green: 0.45, blue: 0.6).opacity(0.5)))
            }
            clipped.stroke(Path(ellipseIn: CGRect(x: -15, y: -15, width: 30, height: 30)), with: .color(faint), lineWidth: 0.6)
            for x in [-69.0, 69] {
                for y in [-22.0, 22] {
                    clipped.stroke(Path(ellipseIn: CGRect(x: x - 15, y: y - 15, width: 30, height: 30)), with: .color(red.opacity(0.6)), lineWidth: 0.5)
                    clipped.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(red))
                }
            }
            context.stroke(boards, with: .color(faint), lineWidth: 0.6)
            for shot in shots.sorted(by: { !$0.isGoal && $1.isGoal }) {
                let radius = shot.isGoal ? 2.6 : 1.6
                let dot = Path(ellipseIn: CGRect(x: shot.x - radius, y: -shot.y - radius, width: radius * 2, height: radius * 2))
                let color = shot.teamId == game.awayTeam.id ? Self.away : shot.teamId == game.homeTeam.id ? Self.home : Self.unknown
                context.fill(dot, with: .color(color.opacity(0.85)))
                if shot.isGoal { context.stroke(dot, with: .color(.white), lineWidth: 0.7) }
            }
        }
        .aspectRatio(208 / 94, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
