import SwiftUI

/// The Expo app's "New" badge on a Continue Watching card whose next episode came out
/// in the last 72 hours (`getRecentEpisodeBadge` in features/home/watch-state-cards.ts):
/// yellow with black text once the episode's prequeue is ready, else grey with white.
struct NewEpisodeBadge: Hashable {
    /// `RECENT_NEXT_EPISODE_BADGE_WINDOW_MS`.
    static let window: TimeInterval = 72 * 3600

    /// The server has the episode's stream resolved (`prequeueStatus == "ready"`).
    let ready: Bool

    /// Nil unless the episode's air time (exact UTC, else the air day from local
    /// midnight) has passed and lies within the window.
    init?(airDate: String?, airDateTimeUTC: String?, prequeueStatus: String?, now: Date = .now) {
        guard let released = ReleaseBadge.airTime(airDate: airDate, airDateTimeUTC: airDateTimeUTC),
              released <= now, now.timeIntervalSince(released) <= Self.window else { return nil }
        ready = prequeueStatus == "ready"
    }
}

/// Sparkles and "New" in a rounded tag, in the Expo badge's colours.
struct NewEpisodeBadgeView: View {
    let badge: NewEpisodeBadge

    /// `RECENT_EPISODE_BADGE_READY_COLOR` / `…_NOT_READY_COLOR`.
    private static let readyColor = Color(red: 0xfa / 255, green: 0xcc / 255, blue: 0x15 / 255)
    private static let notReadyColor = Color(red: 0x6b / 255, green: 0x72 / 255, blue: 0x80 / 255)

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
            Text("New")
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(badge.ready ? Color.black : Color.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(badge.ready ? Self.readyColor : Self.notReadyColor))
        .accessibilityLabel(Text("New episode"))
    }
}
