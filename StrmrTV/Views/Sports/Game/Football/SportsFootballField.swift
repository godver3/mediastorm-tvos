import SwiftUI

/// The football drawings' units (Expo's 840 × 360 view box): goal lines at x 78 and 768, end
/// zones 60 wide outside them, the turf from y 28 to 334.
enum SportsFieldSpace {
    static let width = 840.0
    static let height = 360.0
    static let top = 28.0
    static let bottom = 334.0

    /// The x of a spot measured from the left goal line.
    static func x(_ yard: Double) -> Double { 78 + yard / 100 * 690 }
}

/// A football field drawn to scale (Expo `FootballPossessionField`'s turf, after
/// `FootballFieldMarkings`): five-yard stripes, yard lines, hash marks and numbers between the
/// goal lines, and each end zone in its side's colour with the side's name and logo. The `left`
/// side attacks right. `marks` draws on top in `SportsFieldSpace` units.
struct SportsFootballField: View {
    let left: SportsTeam
    let right: SportsTeam
    /// The sides' colours as `#rrggbb` (`SportsTeamColors.hexPair`).
    let leftColor: String
    let rightColor: String
    var marks: (inout GraphicsContext) -> Void = { _ in }

    var body: some View {
        Canvas { context, size in
            let scale = size.width / SportsFieldSpace.width
            context.scaleBy(x: scale, y: scale)
            turf(&context)
            endZone(&context, team: left, hex: leftColor, x: 18, rotation: -90)
            endZone(&context, team: right, hex: rightColor, x: 768, rotation: 90)
            lines(&context)
            marks(&context)
        }
        .overlay {
            GeometryReader { proxy in
                let scale = proxy.size.width / SportsFieldSpace.width
                logo(left, center: CGPoint(x: 48, y: 60), rotation: -90, scale: scale)
                logo(right, center: CGPoint(x: 798, y: 302), rotation: 90, scale: scale)
            }
        }
        .aspectRatio(SportsFieldSpace.width / SportsFieldSpace.height, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func turf(_ context: inout GraphicsContext) {
        for index in 0..<10 {
            let x = SportsFieldSpace.x(Double(index) * 10)
            let stripe = CGRect(x: x, y: SportsFieldSpace.top, width: 69, height: SportsFieldSpace.bottom - SportsFieldSpace.top)
            context.fill(Path(stripe), with: .color(index % 2 == 0 ? Self.turfDark : Self.turfLight))
        }
    }

    private func endZone(_ context: inout GraphicsContext, team: SportsTeam, hex: String, x: Double, rotation: Double) {
        let fill = Color(hex: hex) ?? .gray
        context.fill(Path(CGRect(x: x, y: SportsFieldSpace.top, width: 60, height: SportsFieldSpace.bottom - SportsFieldSpace.top)),
                     with: .color(fill))
        let name = (team.nickname.flatMap { $0.isEmpty ? nil : $0 } ?? team.name).uppercased()
        let ink: Color = SportsTeamColors.contrast(hex, "#ffffff") >= 4.5 ? .white : .black
        var label = context
        label.translateBy(x: x + 30, y: 181)
        label.rotate(by: .degrees(rotation))
        label.draw(Text(name).font(.system(size: name.count > 20 ? 11 : 16, weight: .bold)).foregroundStyle(ink), at: .zero)
    }

    private func lines(_ context: inout GraphicsContext) {
        for index in 0...20 {
            let x = SportsFieldSpace.x(Double(index) * 5)
            let line = Path { $0.move(to: CGPoint(x: x, y: SportsFieldSpace.top)); $0.addLine(to: CGPoint(x: x, y: SportsFieldSpace.bottom)) }
            context.stroke(line, with: .color(Self.chalk.opacity(index % 2 == 1 ? 0.22 : 0.45)),
                           lineWidth: index == 0 || index == 20 ? 2 : 1)
        }
        var hashes = Path()
        for yard in 1...99 where yard % 5 != 0 {
            let x = SportsFieldSpace.x(Double(yard))
            for top in [29.0, 178, 323] {
                hashes.move(to: CGPoint(x: x, y: top))
                hashes.addLine(to: CGPoint(x: x, y: top + 10))
            }
        }
        context.stroke(hashes, with: .color(Self.hash.opacity(0.6)), lineWidth: 1)
        for y in [52.0, 310] {
            for index in 1...9 {
                let number = Text("\(min(index, 10 - index) * 10)").font(.system(size: 17, weight: .bold)).foregroundStyle(Self.numbers)
                context.draw(number, at: CGPoint(x: SportsFieldSpace.x(Double(index) * 10), y: y))
            }
        }
    }

    private func logo(_ team: SportsTeam, center: CGPoint, rotation: Double, scale: CGFloat) -> some View {
        SportsTeamLogo(team: team, size: 42 * scale)
            .rotationEffect(.degrees(rotation))
            .position(x: center.x * scale, y: center.y * scale)
            .opacity(team.logo == nil ? 0 : 1)
    }

    static let turfDark = Color(red: 0.03, green: 0.33, blue: 0.2)
    static let turfLight = Color(red: 0.03, green: 0.36, blue: 0.21)
    static let chalk = Color(red: 0.86, green: 0.94, blue: 0.89)
    static let hash = Color(red: 0.72, green: 0.84, blue: 0.76)
    static let numbers = Color(red: 0.93, green: 0.97, blue: 0.95)
    /// The ball spot (blue) and the line to gain (yellow), as Expo marks them.
    static let ball = Color(red: 0.19, green: 0.75, blue: 1)
    static let ballDot = Color(red: 0, green: 0.62, blue: 1)
    static let lineToGain = Color(red: 1, green: 0.86, blue: 0.23)
}

extension GraphicsContext {
    /// A play's lane (Expo's ribbon): a band from `x1` to `x2` with a pointed head, or a dot when
    /// the play didn't move.
    func lane(x1: Double, x2: Double, y: Double, halfHeight: Double, fill: Color, stroke: Double) {
        guard x1 != x2 else {
            dot(x: x1, y: y, radius: max(3, halfHeight * 0.5), fill: fill, stroke: stroke)
            return
        }
        let sign: Double = x2 < x1 ? -1 : 1
        let tip = min(9, abs(x2 - x1) / 2)
        var path = Path()
        path.move(to: CGPoint(x: x1, y: y - halfHeight))
        path.addLine(to: CGPoint(x: x2 - sign * tip, y: y - halfHeight))
        path.addLine(to: CGPoint(x: x2, y: y))
        path.addLine(to: CGPoint(x: x2 - sign * tip, y: y + halfHeight))
        path.addLine(to: CGPoint(x: x1, y: y + halfHeight))
        path.closeSubpath()
        self.fill(path, with: .color(fill))
        self.stroke(path, with: .color(.white), lineWidth: stroke)
    }

    /// A drive's arrow (Expo `Arrow`): a line from `x1` to `x2` with an open head, a dot where it
    /// started and, for the drive in progress or a score, a bigger dot where it ended.
    func arrow(x1: Double, x2: Double, y: Double, color: Color, current: Bool, score: Bool, width: Double = 3, dot size: Double = 1) {
        let ink = current ? Color.white : color
        var line = Path()
        line.move(to: CGPoint(x: x1, y: y))
        line.addLine(to: CGPoint(x: x2, y: y))
        stroke(line, with: .color(ink), lineWidth: current ? width + 2 : width)
        if x1 != x2 {
            let back = (x2 >= x1 ? 1 : -1) * min(8 * size, abs(x2 - x1))
            var head = Path()
            head.move(to: CGPoint(x: x2 - back, y: y - 5 * size))
            head.addLine(to: CGPoint(x: x2, y: y))
            head.addLine(to: CGPoint(x: x2 - back, y: y + 5 * size))
            stroke(head, with: .color(ink), lineWidth: 2 * size)
        }
        dot(x: x1, y: y, radius: 3 * size, fill: color, stroke: size)
        if current || score { dot(x: x2, y: y, radius: (current ? 7 : 6) * size, fill: color, stroke: 2 * size) }
    }

    func dot(x: Double, y: Double, radius: Double, fill: Color, stroke: Double) {
        let circle = Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        self.fill(circle, with: .color(fill))
        self.stroke(circle, with: .color(.white), lineWidth: stroke)
    }

    /// A full-height line across the turf at a spot (the ball, the line to gain), in
    /// `SportsFieldSpace` units.
    func yardLine(_ yard: Double, color: Color, width: Double) {
        let x = SportsFieldSpace.x(yard)
        var line = Path()
        line.move(to: CGPoint(x: x, y: SportsFieldSpace.top))
        line.addLine(to: CGPoint(x: x, y: SportsFieldSpace.bottom))
        stroke(line, with: .color(color), lineWidth: width)
    }
}
