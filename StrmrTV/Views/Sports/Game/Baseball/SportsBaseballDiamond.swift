import SwiftUI

/// The infield drawn natively (Expo `Diamond`): the base paths, the mound and home plate, and
/// first, second and third, gold with a runner on, white when empty, dashed outlines when the
/// feed didn't say who is on.
struct SportsBaseballDiamond: View {
    /// First, second and third (`SportsBaseballSituation.occupiedBases`); nil when unknown.
    let bases: [Bool]?
    var size: CGFloat = 150

    var body: some View {
        Canvas { context, canvas in
            let scale = canvas.width / 120
            context.scaleBy(x: scale, y: scale)
            context.fill(Self.square(center: CGPoint(x: 60, y: 60), half: 56), with: .color(Color.white.opacity(0.08)))
            context.stroke(Self.square(center: CGPoint(x: 60, y: 60), half: 46), with: .color(Color.white.opacity(0.55)), lineWidth: 2)
            context.fill(Path(ellipseIn: CGRect(x: 51, y: 56, width: 18, height: 18)), with: .color(Color.white.opacity(0.2)))
            for (index, spot) in [CGPoint(x: 106, y: 60), CGPoint(x: 60, y: 14), CGPoint(x: 14, y: 60)].enumerated() {
                let base = Self.square(center: spot, half: 10)
                let occupied = bases?[index] == true
                if let bases { context.fill(base, with: .color(bases[index] ? Self.runner : .white)) }
                context.stroke(base, with: .color(occupied ? Self.runner : Color.white.opacity(0.55)),
                               style: StrokeStyle(lineWidth: 2, dash: bases == nil ? [3, 3] : []))
            }
            var plate = Path()
            plate.addLines([CGPoint(x: 53, y: 100), CGPoint(x: 67, y: 100), CGPoint(x: 67, y: 107), CGPoint(x: 60, y: 113),
                            CGPoint(x: 53, y: 107)])
            plate.closeSubpath()
            context.fill(plate, with: .color(Color.white.opacity(0.55)))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// A square standing on its corner around `center`.
    private static func square(center: CGPoint, half: CGFloat) -> Path {
        var path = Path()
        path.addLines([CGPoint(x: center.x, y: center.y - half), CGPoint(x: center.x + half, y: center.y),
                       CGPoint(x: center.x, y: center.y + half), CGPoint(x: center.x - half, y: center.y)])
        path.closeSubpath()
        return path
    }

    /// A base with a runner on.
    static let runner = Color(red: 1, green: 0.83, blue: 0.36)
}

/// Balls, strikes and outs as lights (Expo `BaseballCount`): green, yellow and red, each row
/// only when the feed reports a plain count; "Last reported" over old data.
struct SportsBaseballCount: View {
    let situation: SportsBaseballSituation?
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if stale { Text("Last reported").font(.caption).foregroundStyle(.secondary) }
            ForEach(Self.rows(situation), id: \.label) { row in
                HStack(spacing: 8) {
                    Text("\(row.label) \(row.value)").font(.caption).monospacedDigit().frame(width: 110, alignment: .leading)
                    ForEach(0..<row.top, id: \.self) { light in
                        Circle().fill(light < row.value ? row.color : .clear)
                            .overlay(Circle().strokeBorder(light < row.value ? row.color : Color.secondary, lineWidth: 1.5))
                            .frame(width: 16, height: 16)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.label): \(row.value)")
            }
        }
    }

    struct Row {
        let label: String
        let value: Int
        let top: Int
        let color: Color
    }

    /// The counts worth showing: balls 0–3, strikes 0–2, outs 0–2.
    static func rows(_ situation: SportsBaseballSituation?) -> [Row] {
        [(String(localized: "Balls"), situation?.balls, 3, Color(red: 0.21, green: 0.8, blue: 0.53)),
         (String(localized: "Strikes"), situation?.strikes, 2, Color(red: 1, green: 0.83, blue: 0.36)),
         (String(localized: "Outs"), situation?.outs, 2, Color(red: 1, green: 0.39, blue: 0.45))]
            .compactMap { label, value, top, color in
                value.flatMap { (0...top).contains($0) ? Row(label: label, value: $0, top: top, color: color) : nil }
            }
    }
}

/// Who is on base at a glance (Expo's hub card diamond): second on top, third and first below,
/// gold with a runner on, an outline when empty. For the scoreboard's situation line and the
/// hub's cards.
struct SportsBasesGlyph: View {
    /// First, second and third.
    let bases: [Bool]
    /// The width of one base.
    var size: CGFloat = 16

    var body: some View {
        let step = size * 0.68
        ZStack {
            base(bases[1]).offset(y: -step)
            base(bases[2]).offset(x: -step)
            base(bases[0]).offset(x: step)
        }
        .frame(width: size + step * 2, height: size + step)
        .offset(y: step / 2)
        .accessibilityHidden(true)
    }

    private func base(_ occupied: Bool) -> some View {
        Rectangle()
            .fill(occupied ? SportsBaseballDiamond.runner : .clear)
            .overlay(Rectangle().strokeBorder(occupied ? SportsBaseballDiamond.runner : Color.secondary, lineWidth: 1.5))
            .frame(width: size / 2.squareRoot(), height: size / 2.squareRoot())
            .rotationEffect(.degrees(45))
    }
}
