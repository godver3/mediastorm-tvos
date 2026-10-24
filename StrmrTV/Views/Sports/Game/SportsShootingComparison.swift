import SwiftUI

/// The Box Score's shooting panel for hockey and basketball (Expo `ShootingComparison`): "Shots &
/// Special Teams" (shots on goal, power-play goals) or "Shooting Splits" (field goals, 3-pointers,
/// free throws) from the game totals, over a rink or court sketch with the first figure of each
/// side, home on the left; basketball rows add each side's made share as a bar. One stop.
struct SportsShootingComparison: View {
    let page: SportsGamePage

    private var hockey: Bool { page.game.league == "nhl" }

    /// The rows the panel shows, in Expo's order; empty for other sports or before the start.
    static func rows(_ page: SportsGamePage) -> [SportsComparison] {
        guard page.lifecycle != .scheduled else { return [] }
        let fields: [String] = page.game.league == "nhl" ? ["shots on goal", "power-play goals"]
            : page.kind == .basketball ? ["field goals", "three-pointers", "free throws"] : []
        return fields.flatMap { field in page.detail.comparisons.filter { $0.label.lowercased() == field } }
    }

    var body: some View {
        let rows = Self.rows(page)
        let game = page.game
        SportsPanel(hockey ? String(localized: "Shots & Special Teams") : String(localized: "Shooting Splits")) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(game.homeTeam.shortName)
                    Spacer()
                    Text(game.awayTeam.shortName)
                }
                .fontWeight(.semibold)
                if let first = rows.first {
                    sketch(first).frame(maxWidth: .infinity)
                    Text("Game totals · shot locations not supplied.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(rows, id: \.label) { row in
                    VStack(spacing: 8) {
                        HStack {
                            Text(row.home).font(.headline).monospacedDigit()
                            Text(row.label).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                            Text(row.away).font(.headline).monospacedDigit()
                        }
                        if !hockey {
                            HStack(spacing: 16) {
                                share(row.home, color: SportsStatusPill.accent)
                                share(row.away, color: Self.amber)
                            }
                        }
                    }
                }
            }
            .sportsReadout()
            .accessibilityLabel(([String(localized: "Shooting comparison")] + rows.map {
                "\($0.label): \(game.homeTeam.shortName) \($0.home), \(game.awayTeam.shortName) \($0.away)"
            }).joined(separator: ". "))
        }
    }

    private static let amber = Color(red: 0.984, green: 0.749, blue: 0.141)

    /// A made–attempted figure's share ("39-87" → 45%); blank otherwise.
    static func share(_ value: String) -> Double? {
        guard let match = value.trimmingCharacters(in: .whitespaces).wholeMatch(of: #/(\d+)-(\d+)/#),
              let made = Double(match.1), let attempts = Double(match.2), attempts > 0, made <= attempts else { return nil }
        return made / attempts
    }

    @ViewBuilder private func share(_ value: String, color: Color) -> some View {
        if let share = Self.share(value) {
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(Color.white.opacity(0.12)).frame(height: 6)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in Capsule().fill(color).frame(width: proxy.size.width * share) }
                    }
                Text(share.formatted(.percent.precision(.fractionLength(0)))).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
        }
    }

    /// Expo's 600 × 170 sketch: a rink (red centre line, blue lines, creases) or a court (keys, arcs,
    /// rims), the first row's figures over each half.
    private func sketch(_ row: SportsComparison) -> some View {
        let hockey = self.hockey
        return Canvas { context, size in
            context.scaleBy(x: size.width / 600, y: size.width / 600)
            let line = Color(red: 0.29, green: 0.39, blue: 0.44), red = Color(red: 0.65, green: 0.28, blue: 0.32)
            let outline = Path(roundedRect: CGRect(x: 10, y: 10, width: 580, height: 150), cornerRadius: hockey ? 65 : 4)
            context.fill(outline, with: .color(Color(red: 0.063, green: 0.133, blue: 0.176)))
            context.stroke(outline, with: .color(line), lineWidth: 2)
            context.stroke(Path { $0.move(to: CGPoint(x: 300, y: 10)); $0.addLine(to: CGPoint(x: 300, y: 160)) },
                           with: .color(hockey ? red : line), lineWidth: 2)
            context.stroke(Path(ellipseIn: CGRect(x: 276, y: 61, width: 48, height: 48)), with: .color(line), lineWidth: 2)
            if hockey {
                for x in [195.0, 405] {
                    context.stroke(Path { $0.move(to: CGPoint(x: x, y: 10)); $0.addLine(to: CGPoint(x: x, y: 160)) },
                                   with: .color(Color(red: 0.22, green: 0.47, blue: 0.68)), lineWidth: 3)
                }
                for x in [25.0, 557] { context.stroke(Path(CGRect(x: x, y: 65, width: 18, height: 40)), with: .color(red), lineWidth: 1) }
            } else {
                for x in [10.0, 505] { context.stroke(Path(CGRect(x: x, y: 50, width: 85, height: 70)), with: .color(line), lineWidth: 1) }
                var arcs = Path()
                arcs.addArc(center: CGPoint(x: 30, y: 85), radius: 72, startAngle: .degrees(-76), endAngle: .degrees(76), clockwise: false)
                arcs.move(to: CGPoint(x: 570 + 72 * cos(Double.pi * 104 / 180), y: 85 - 72 * sin(Double.pi * 104 / 180)))
                arcs.addArc(center: CGPoint(x: 570, y: 85), radius: 72, startAngle: .degrees(256), endAngle: .degrees(104), clockwise: true)
                context.stroke(arcs, with: .color(line), lineWidth: 1)
                for x in [35.0, 565] {
                    context.stroke(Path(ellipseIn: CGRect(x: x - 7, y: 78, width: 14, height: 14)), with: .color(.orange), lineWidth: 1.5)
                }
            }
            let caption = hockey ? String(localized: "SHOTS ON GOAL") : String(localized: "FIELD GOALS")
            for (x, value, color) in [(210.0, row.home, SportsStatusPill.accent), (390.0, row.away, Self.amber)] {
                context.draw(Text(value).font(.system(size: 30, weight: .bold)).foregroundStyle(color), at: CGPoint(x: x, y: 70))
                context.draw(Text(caption).font(.system(size: 13)).foregroundStyle(Color(red: 0.69, green: 0.73, blue: 0.8)),
                             at: CGPoint(x: x, y: 104))
            }
        }
        .aspectRatio(600 / 170, contentMode: .fit)
        .frame(maxWidth: 720)
        .accessibilityHidden(true)
    }
}
