import SwiftUI

/// The Overview's court (Expo `SportsBasketballLiveCard` on TV): the shot chart, every attempt by
/// side (made filled, missed a ring; the away side shoots at the left basket), the latest shot
/// marked with a basketball that pulses while the game is live, and its card ("Latest shot" /
/// "Last shot": the player, "+2 PTS" or "Missed", when) in a corner away from it, or under the court
/// when there is no room. Not before the start, nor without shots, shooting totals or plays. One
/// stop for the remote, as in Expo.
struct SportsBasketballCourtCard: View {
    let page: SportsGamePage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var courtWidth: CGFloat = 0

    private static let cardSize = CGSize(width: 0.48, height: 112)

    static func shows(_ page: SportsGamePage) -> Bool {
        guard page.lifecycle != .scheduled else { return false }
        let detail = page.detail
        return !detail.basketballShots.isEmpty || !detail.plays.isEmpty || page.game.liveBasketballSituation != nil
            || detail.comparisons.contains { SportsFormat.matches(#"^field goals$|three.point|three pointer|3pt"#, $0.label) }
    }

    var body: some View {
        let game = page.game
        let geometry = SportsCourtGeometry(league: game.league, home: game.homeTeam)
        let colors = SportsTeamColors.chartPair(away: game.awayTeam, home: game.homeTeam)
        let color = { (team: String) in Color(hex: team == game.awayTeam.id ? colors.away : colors.home) ?? .white }
        let marks = page.detail.basketballShots.compactMap { shot in
            SportsCourtGeometry.position(of: shot, in: game).map { (spot: $0, color: color(shot.teamId), made: shot.made) }
        }
        let latest = page.detail.basketballShots.last
        let scale = courtWidth / SportsCourtGeometry.size.width
        let marker = latest.flatMap { SportsCourtGeometry.position(of: $0, in: game) }
            .map { CGPoint(x: ($0.x - 40) * scale, y: ($0.y - 40) * scale) }
        let card = CGSize(width: courtWidth * Self.cardSize.width, height: Self.cardSize.height)
        let corner = marker.flatMap { marker in
            courtWidth >= 600 ? SportsCourtGeometry.cardPlacement(in: CGSize(width: courtWidth, height: courtWidth * 500 / 940),
                                                                  card: card, marker: marker, clearance: 40, inset: 12) : nil
        }
        SportsPanel(String(localized: "Shot Chart"), note: legend) {
            VStack(alignment: .leading, spacing: 16) {
                SportsBasketballCourt(geometry: geometry, home: game.homeTeam, marks: marks)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { courtWidth = $0 }
                    .overlay {
                        ZStack(alignment: .topLeading) {
                            Color.clear
                            if let marker {
                                self.marker.position(marker)
                            }
                            if let latest, let corner {
                                shotCard(latest, color: color(latest.teamId), compact: true)
                                    .frame(width: card.width, height: card.height)
                                    .offset(x: corner.x, y: corner.y)
                            }
                        }
                    }
                if let latest, corner == nil {
                    shotCard(latest, color: color(latest.teamId), compact: false)
                } else if latest == nil {
                    Text(label).font(.callout.weight(.semibold))
                }
                if let bonus = game.liveBasketballSituation?.bonus {
                    Text(bonus).font(.caption).foregroundStyle(.secondary)
                }
            }
            .sportsReadout()
            .accessibilityLabel(spoken)
        }
        .task { pulse = true }
    }

    private var label: String {
        let live = page.lifecycle == .live
        if page.detail.basketballShots.isEmpty { return live ? String(localized: "Live court") : String(localized: "Game snapshot") }
        return live ? String(localized: "Latest shot") : String(localized: "Last shot")
    }

    private var legend: String? {
        guard !page.detail.basketballShots.isEmpty else { return nil }
        let game = page.game
        return String(localized: "\(game.awayTeam.shortName) shoots left, \(game.homeTeam.shortName) right · Filled: made · Ring: missed")
    }

    private var spoken: String {
        let situation = page.game.liveBasketballSituation.map { "\(page.game.side(named: $0.possession)?.name ?? $0.possession) possession. " } ?? ""
        let latest = page.detail.basketballShots.last?.description ?? page.detail.plays.first.map { $0.description ?? $0.title }
        return "\(label). \(situation)\(latest ?? String(localized: "Team shooting totals"))"
    }

    /// The latest shot: Expo's dark disk with a basketball, and a ring that pulses while live.
    private var marker: some View {
        ZStack {
            if page.lifecycle == .live && !reduceMotion {
                // Only the ring's growth repeats; the marker's moves aren't animated.
                Circle().stroke(Color.white, lineWidth: 2)
                    .animation(.linear(duration: 2.2).repeatForever(autoreverses: false)) { ring in
                        ring.scaleEffect(pulse ? 2.3 : 1).opacity(pulse ? 0 : 0.45)
                    }
            }
            Circle().fill(Color(red: 0.02, green: 0.03, blue: 0.05))
            Circle().strokeBorder(Color.white, lineWidth: 2.5)
            Image(systemName: "basketball.fill").font(.system(size: 20)).foregroundStyle(Color(red: 1, green: 0.76, blue: 0.35))
        }
        .frame(width: 34, height: 34)
    }

    private func shotCard(_ shot: SportsBasketballShot, color: Color, compact: Bool) -> some View {
        HStack(spacing: 14) {
            if shot.headshotUrl != nil || shot.jersey != nil {
                SportsPlayerPortrait(name: shot.playerName ?? "", headshot: shot.headshotUrl,
                                     team: page.team(id: shot.teamId), size: compact ? 56 : 72)
            }
            VStack(alignment: .leading, spacing: 4) {
                if compact { Text(label).font(.caption2).foregroundStyle(.secondary) }
                HStack(spacing: 10) {
                    Text(shot.playerName ?? String(localized: "Shot details"))
                        .font(compact ? .caption.weight(.semibold) : .callout.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    if !compact, let jersey = shot.jersey { Text("#\(jersey)").font(.caption).foregroundStyle(.secondary) }
                }
                HStack(spacing: 10) {
                    Text(shot.made ? "+\(shot.points) PTS" : compact ? String(localized: "Missed") : String(localized: "Missed shot"))
                        .font(.caption.weight(.bold)).foregroundStyle(color)
                    Text([shot.periodLabel, shot.clock].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                if !compact, !shot.description.isEmpty {
                    Text(shot.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(compact ? 10 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(red: 0.07, green: 0.1, blue: 0.13).opacity(0.94)))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 4).padding(.vertical, 8) }
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1) }
    }
}
