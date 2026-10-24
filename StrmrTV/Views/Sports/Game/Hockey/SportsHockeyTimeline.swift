import SwiftUI

/// The hockey Overview's events (Expo `SportsMatchTimeline`, compact): a final's last three goals
/// ("Scoring Highlights"), otherwise the newest event ("Latest Event", "Last Available Event" when
/// the data is old), each with its type's symbol in the side's colour, "12:05 · P3 · BOS", the title,
/// the goal badge and the narrative. Full history in Play-by-Play. One stop per event.
struct SportsHockeyTimeline: View {
    let page: SportsGamePage

    /// Expo `sportsTimelineEvents`: each play once and only with text, newest first; for a final,
    /// goals and penalties (or scoring plays) when there are any.
    static func events(_ page: SportsGamePage) -> [SportsPlay] {
        guard page.lifecycle != .scheduled else { return [] }
        let final = page.lifecycle == .final
        let source = final ? page.detail.plays.filter { $0.scoring || SportsEventKind(title: $0.title) == .goal } : page.detail.plays
        var seen = Set<String>()
        let meaningful = source.filter { play in
            let text = !play.title.trimmingCharacters(in: .whitespaces).isEmpty
                || !(play.description ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            return text && seen.insert(play.id).inserted
        }
        let key = meaningful.filter { [.goal, .penalty].contains(SportsEventKind(title: $0.title)) || $0.scoring }
        let picked = final && !key.isEmpty ? key : meaningful
        return Array(picked.prefix(final ? 3 : 1))
    }

    var body: some View {
        let events = Self.events(page)
        SportsPanel(title, note: String(localized: "Latest update · Full history in Play-by-Play")) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, play in
                row(play, last: index == events.count - 1)
            }
        }
    }

    private var title: String {
        if page.lifecycle == .final { return String(localized: "Scoring Highlights") }
        return page.isStale() ? String(localized: "Last Available Event") : String(localized: "Latest Event")
    }

    private func row(_ play: SportsPlay, last: Bool) -> some View {
        let team = page.team(id: play.teamId)
        let color = team.map { SportsTeamColors.color($0, in: page.game) } ?? .secondary
        let time = [play.clock, play.periodLabel].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
        return HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 6) {
                Image(systemName: SportsHockeyEvent(play).symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                if !last { Rectangle().fill(Color.white.opacity(0.15)).frame(width: 2).frame(maxHeight: .infinity) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text([time.isEmpty ? String(localized: "Time not supplied") : time, team?.shortName,
                      play.shootout ? String(localized: "Shootout") : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Text(play.title.isEmpty ? String(localized: "Reported event") : play.title).fontWeight(.semibold)
                if let badge = SportsHockeyGoalBadge(play) { SportsHockeyGoalBadgeTag(badge: badge) }
                if let description = play.description, !description.isEmpty {
                    Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                } else if !play.participants.isEmpty {
                    Text(play.participants.map(\.name).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .sportsReadout()
    }
}
