import SwiftUI

/// The court drawn natively (Expo `SportsBasketballLiveCard`'s court): the floor (wood, Boston's
/// parquet or Brooklyn's herringbone), both lanes painted in the home colour, the lines, backboards
/// and rims, the home logo at centre court, then every shot of the chart: made shots filled, missed
/// ones as rings, each in its side's colour. In `SportsCourtGeometry` units scaled to the width.
struct SportsBasketballCourt: View {
    let geometry: SportsCourtGeometry
    let home: SportsTeam
    /// Shots to mark: drawing-unit spot, colour, made.
    let marks: [(spot: CGPoint, color: Color, made: Bool)]

    private static let line = Color(red: 0.945, green: 0.91, blue: 0.843)

    var body: some View {
        Canvas { context, size in
            let scale = size.width / SportsCourtGeometry.size.width
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -SportsCourtGeometry.origin.x, y: -SportsCourtGeometry.origin.y)
            context.clip(to: Path(CGRect(origin: SportsCourtGeometry.origin, size: SportsCourtGeometry.size)))
            floor(&context)
            lines(&context)
            for mark in marks {
                let dot = Path(ellipseIn: CGRect(x: mark.spot.x - 7, y: mark.spot.y - 7, width: 14, height: 14))
                if mark.made {
                    context.fill(dot, with: .color(mark.color))
                    context.stroke(dot, with: .color(.black.opacity(0.55)), lineWidth: 1.5)
                } else {
                    context.stroke(dot, with: .color(mark.color), lineWidth: 3)
                }
            }
        }
        .overlay {
            GeometryReader { proxy in
                let side = 190 * proxy.size.width / SportsCourtGeometry.size.width
                SportsTeamLogo(team: home, size: side).opacity(0.88)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
        .aspectRatio(SportsCourtGeometry.size.width / SportsCourtGeometry.size.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }

    private func floor(_ context: inout GraphicsContext) {
        switch geometry.floor {
        case .wood:
            context.fill(Path(CGRect(x: 40, y: 40, width: 940, height: 500)), with: .color(Color(hex: "#a18b69") ?? .brown))
            for row in 0..<25 {
                let y = 40 + Double(row) * 20
                context.fill(Path(CGRect(x: 40, y: y, width: 940, height: 20)),
                             with: .color((Color(hex: row % 2 == 0 ? "#927b5c" : "#baa079") ?? .brown).opacity(0.2)))
                context.stroke(Path { $0.move(to: CGPoint(x: 40, y: y)); $0.addLine(to: CGPoint(x: 980, y: y)) },
                               with: .color(Color(hex: "#604d36")?.opacity(0.18) ?? .clear), lineWidth: 1)
                for joint in 0..<4 {
                    let x = 80 + Double(joint) * 240 + Double(row % 3) * 55
                    context.stroke(Path { $0.move(to: CGPoint(x: x, y: y)); $0.addLine(to: CGPoint(x: x, y: y + 20)) },
                                   with: .color(Color(hex: "#604d36")?.opacity(0.16) ?? .clear), lineWidth: 1)
                }
            }
        case .parquet:
            for tileX in stride(from: 40.0, to: 980, by: 80) {
                for tileY in stride(from: 40.0, to: 540, by: 80) {
                    let across = (Int((tileX - 40) / 80) + Int((tileY - 40) / 80)) % 2 == 0
                    context.fill(Path(CGRect(x: tileX, y: tileY, width: 80, height: 80)),
                                 with: .color(Color(hex: across ? "#b99b70" : "#9e805a") ?? .brown))
                    for grain in 1...4 {
                        let offset = Double(grain) * 16
                        let path = Path { path in
                            path.move(to: across ? CGPoint(x: tileX, y: tileY + offset) : CGPoint(x: tileX + offset, y: tileY))
                            path.addLine(to: across ? CGPoint(x: tileX + 80, y: tileY + offset) : CGPoint(x: tileX + offset, y: tileY + 80))
                        }
                        context.stroke(path, with: .color(Color(hex: "#735b3b")?.opacity(0.3) ?? .clear), lineWidth: 1)
                    }
                }
            }
        case .herringbone:
            context.fill(Path(CGRect(x: 40, y: 40, width: 940, height: 500)), with: .color(Color(hex: "#919394") ?? .gray))
            var tiles = context
            tiles.translateBy(x: 510, y: 290)
            tiles.rotate(by: .degrees(45))
            for i in -40...40 {
                for j in -10...10 {
                    let x = Double(i + 4 * j) * 16, y = Double(-i + 4 * j) * 16
                    for (rect, fill) in [(CGRect(x: x, y: y, width: 64, height: 16), "#a2a4a5"),
                                         (CGRect(x: x + 64, y: y, width: 16, height: 64), "#8d9092")]
                    where abs(rect.midX) < 760 && abs(rect.midY) < 760 {
                        tiles.fill(Path(rect), with: .color(Color(hex: fill) ?? .gray))
                        tiles.stroke(Path(rect), with: .color(Color(hex: "#777b7d") ?? .gray), lineWidth: 0.8)
                    }
                }
            }
        }
    }

    private func lines(_ context: inout GraphicsContext) {
        let paint = Color(hex: geometry.paint) ?? .gray
        let mid = SportsCourtGeometry.midline, lane = geometry.laneHalf
        func stroke(_ path: Path, _ dash: [CGFloat]) {
            context.stroke(path, with: .color(Self.line), style: StrokeStyle(lineWidth: 2, dash: dash))
        }
        for x in [40.0, 790] {
            let rect = Path(CGRect(x: x, y: mid - lane, width: 190, height: lane * 2))
            context.fill(rect, with: .color(paint.opacity(0.88)))
            stroke(rect, [])
        }
        stroke(Path(CGRect(x: 40, y: 40, width: 940, height: 500)), [])
        stroke(Path { $0.move(to: CGPoint(x: 510, y: 40)); $0.addLine(to: CGPoint(x: 510, y: 540)) }, [])
        for radius in [60.0, 20] { stroke(Path(ellipseIn: CGRect(x: 510 - radius, y: mid - radius, width: radius * 2, height: radius * 2)), []) }
        // Free-throw circles: solid toward centre court, dashed toward the baseline.
        for (x, towardCentre) in [(230.0, true), (790.0, false)] {
            let centre = CGPoint(x: x, y: mid)
            stroke(Path { $0.addArc(center: centre, radius: 60, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: towardCentre) }, [])
            stroke(Path { $0.addArc(center: centre, radius: 60, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: !towardCentre) }, [8, 8])
        }
        var ticks = Path()
        for x in [110.0, 150, 180, 210, 810, 840, 870, 910] {
            ticks.move(to: CGPoint(x: x, y: mid - lane)); ticks.addLine(to: CGPoint(x: x, y: mid - lane - 6))
            ticks.move(to: CGPoint(x: x, y: mid + lane)); ticks.addLine(to: CGPoint(x: x, y: mid + lane + 6))
        }
        for (start, end) in [((320.0, 40.0), (320.0, 70.0)), ((700, 40), (700, 70)), ((320, 540), (320, 510)), ((700, 540), (700, 510)),
                             ((40, 180), (46, 180)), ((40, 400), (46, 400)), ((980, 180), (974, 180)), ((980, 400), (974, 400))] {
            ticks.move(to: CGPoint(x: start.0, y: start.1)); ticks.addLine(to: CGPoint(x: end.0, y: end.1))
        }
        stroke(ticks, [])
        stroke(geometry.threePointLine, [])
        if geometry.restricted {
            for (rim, side) in [(SportsCourtGeometry.leftRim, 1.0), (SportsCourtGeometry.rightRim, -1.0)] {
                stroke(Path { path in
                    path.move(to: CGPoint(x: rim - side * 12.5, y: 250))
                    path.addLine(to: CGPoint(x: rim, y: 250))
                    path.addArc(center: CGPoint(x: rim, y: mid), radius: 40, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: side > 0)
                    path.addLine(to: CGPoint(x: rim - side * 12.5, y: 330))
                }, [])
            }
        }
        for x in [80.0, 940] {
            context.stroke(Path { $0.move(to: CGPoint(x: x, y: 260)); $0.addLine(to: CGPoint(x: x, y: 320)) },
                           with: .color(Color(hex: "#fff3dc") ?? .white), lineWidth: 4)
        }
        for x in [SportsCourtGeometry.leftRim, SportsCourtGeometry.rightRim] {
            context.stroke(Path(ellipseIn: CGRect(x: x - 7.5, y: mid - 7.5, width: 15, height: 15)),
                           with: .color(Color(hex: "#ffac64") ?? .orange), lineWidth: 3)
        }
    }
}
