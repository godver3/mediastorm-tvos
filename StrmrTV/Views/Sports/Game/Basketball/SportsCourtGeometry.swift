import SwiftUI

/// The basketball court in drawing units (Expo `basketball-court.ts`, 10 units a foot): the
/// 940 × 500 playing area from (40, 40), rims at x 92.5 and 927.5 on the y 290 midline. The lane,
/// three-point line and restricted area follow the league; the paint takes the home colour, and
/// Boston and Brooklyn keep their parquet and herringbone floors. Shots are team-oriented: the away
/// side attacks the left basket, the home side the right (never the broadcast's direction).
struct SportsCourtGeometry: Equatable {
    enum Floor: Equatable { case wood, parquet, herringbone }

    static let origin = CGPoint(x: 40, y: 40)
    static let size = CGSize(width: 940, height: 500)
    static let midline = 290.0
    static let leftRim = 92.5
    static let rightRim = 927.5

    /// Half the lane's width.
    let laneHalf: Double
    let restricted: Bool
    let floor: Floor
    let threeRadius: Double
    let cornerDistance: Double
    /// The home side's paint colour (`#rrggbb`); a neutral grey without one.
    let paint: String

    init(league: String, home: SportsTeam) {
        let college = league.contains("college-basketball")
        laneHalf = college ? 60 : 80
        restricted = league != "womens-college-basketball"
        floor = league == "nba" && home.id == "2" ? .parquet : league == "nba" && home.id == "17" ? .herringbone : .wood
        threeRadius = league == "nba" ? 237.5 : (22 + 1.75 / 12) * 10
        cornerDistance = college ? (21 + 7.375 / 12) * 10 : 220
        let hex = home.color.map { $0.replacingOccurrences(of: "#", with: "") } ?? ""
        paint = hex.count == 6 && UInt32(hex, radix: 16) != nil ? "#" + hex.lowercased() : "#545e65"
    }

    /// Both three-point lines: straight from the baseline to the corner, then the arc around the rim
    /// (two cubic segments per side, as Expo draws it).
    var threePointLine: Path {
        let offset = (threeRadius * threeRadius - cornerDistance * cornerDistance).squareRoot()
        let k = 4.0 / 3.0 * tan(asin(cornerDistance / threeRadius) / 4)
        let low = Self.midline - cornerDistance, high = Self.midline + cornerDistance
        var path = Path()
        for side in [1.0, -1.0] {
            let rim = side == 1 ? Self.leftRim : Self.rightRim, edge = side == 1 ? 40.0 : 980.0
            let x = rim + side * offset, apex = rim + side * threeRadius
            path.move(to: CGPoint(x: edge, y: low))
            path.addLine(to: CGPoint(x: x, y: low))
            path.addCurve(to: CGPoint(x: apex, y: Self.midline), control1: CGPoint(x: x + side * k * cornerDistance, y: low + k * offset),
                          control2: CGPoint(x: apex, y: Self.midline - k * threeRadius))
            path.addCurve(to: CGPoint(x: x, y: high), control1: CGPoint(x: apex, y: Self.midline + k * threeRadius),
                          control2: CGPoint(x: x + side * k * cornerDistance, y: high - k * offset))
            path.addLine(to: CGPoint(x: edge, y: high))
        }
        return path
    }

    /// Where a shot was taken (Expo `basketballShotPosition`), in drawing units; nil for a side not
    /// in this game or a spot off the court.
    static func position(of shot: SportsBasketballShot, in game: SportsGame) -> CGPoint? {
        guard [game.awayTeam.id, game.homeTeam.id].contains(shot.teamId), shot.x.isFinite, shot.y.isFinite,
              (0...50).contains(shot.x), (-5.25...88.75).contains(shot.y) else { return nil }
        return shot.teamId == game.awayTeam.id
            ? CGPoint(x: leftRim + shot.y * 10, y: 40 + shot.x * 10)
            : CGPoint(x: rightRim - shot.y * 10, y: 540 - shot.x * 10)
    }

    /// A corner for the latest shot's card away from its marker (Expo `basketballShotCardPlacement`),
    /// keeping `clearance` around the marker; nil when the card doesn't fit beside it.
    static func cardPlacement(in size: CGSize, card: CGSize, marker: CGPoint, clearance: CGFloat, inset: CGFloat) -> CGPoint? {
        guard size.width > 0, size.height > 0, card.width + 2 * inset <= size.width / 2, card.height + 2 * inset <= size.height
        else { return nil }
        let left = marker.x < size.width / 2 ? size.width - card.width - inset : inset
        let tops = marker.y < size.height / 2 ? [size.height - card.height - inset, inset] : [inset, size.height - card.height - inset]
        for top in tops {
            let dx = marker.x - max(left, min(marker.x, left + card.width))
            let dy = marker.y - max(top, min(marker.y, top + card.height))
            if dx * dx + dy * dy > clearance * clearance { return CGPoint(x: left, y: top) }
        }
        return nil
    }
}
