import SwiftUI

/// What holds focus in the race page's controls.
enum SportsRaceFocus: Hashable {
    case watch, session, spoilers
    case tab(SportsRaceTab)
}

/// The race page's top (Expo's editorial header and event context): series and the shown
/// session's status, the weekend's title and the session's line (type, state, place, time),
/// then Watch Live / Find Streams, the session picker (a menu of the weekend's sessions) and
/// Hide Scores, and the page's tabs (none while scores are hidden).
struct SportsRaceHeader: View {
    @ObservedObject var model: SportsRacePageModel
    let weekend: SportsRaceEvent
    let leagueName: String
    let spoilers: Bool
    let focus: FocusState<SportsRaceFocus?>.Binding
    let watch: (SportsWatchTarget) -> Void

    var body: some View {
        let session = model.detail
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 18) {
                Text(leagueName.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if let session { SportsStatusPill(lifecycle: session.lifecycle) }
            }
            Text(weekend.title.trimmingCharacters(in: .whitespaces)).font(.system(size: 52, weight: .semibold)).lineLimit(2)
            Text(contextLine(session)).font(.headline)
            controls(session).padding(.top, 18)
            if !spoilers {
                tabRow.padding(.top, 8)
            }
        }
    }

    private func contextLine(_ session: SportsRaceEvent?) -> String {
        if model.tab == .championship && !spoilers { return String(localized: "Championship standings") }
        guard let session else { return String(localized: "Race weekend") }
        return SportsRaceFormat.contextLine(session, weekend: weekend)
    }

    private func controls(_ session: SportsRaceEvent?) -> some View {
        HStack(spacing: 24) {
            if let target = session.flatMap({ Self.watchTarget(weekend, $0) }) {
                Button { watch(target) } label: {
                    Label(target.live ? "Watch Live" : "Find Streams", systemImage: "play.fill")
                }
                .focused(focus, equals: .watch)
                .accessibilityIdentifier("sports-race-watch")
            }
            if weekend.sessions.count > 1 {
                Menu {
                    Picker("Session", selection: Binding(get: { model.session?.id ?? "" }, set: { model.select($0) })) {
                        ForEach(weekend.sessions) { Text(SportsRaceFormat.sessionOption($0)).tag($0.id) }
                    }
                } label: {
                    Label("Session: \(session?.sessionType ?? String(localized: "Choose"))", systemImage: "chevron.down")
                }
                .focused(focus, equals: .session)
                .accessibilityIdentifier("sports-race-session")
            }
            Button { SportsSpoilers.shared.hidden.toggle() } label: {
                Label(spoilers ? "Show Scores" : "Hide Scores", systemImage: spoilers ? "eye" : "eye.slash")
            }
            .focused(focus, equals: .spoilers)
            .accessibilityIdentifier("sports-race-spoilers")
        }
        .sportsChipRow()
    }

    private var tabRow: some View {
        HStack(spacing: 18) {
            ForEach(model.tabs) { tab in
                Button(tab.label) { model.tab = tab }
                    .buttonStyle(FilterChipStyle(selected: tab == model.tab))
                    .focused(focus, equals: .tab(tab))
                    .accessibilityIdentifier("sports-race-tab-\(tab.rawValue)")
            }
        }
        .font(.callout)
        .lineLimit(1)
        .sportsChipRow()
        .defaultFocus(focus, .tab(model.tab), priority: .userInitiated)
    }

    /// What Watch searches for (Expo `raceWatchTarget`): the session with its weekend, while it is
    /// live or yet to run and neither is stale (the server then can't match it).
    static func watchTarget(_ weekend: SportsRaceEvent, _ session: SportsRaceEvent) -> SportsWatchTarget? {
        guard !weekend.stale, !session.stale, [.live, .scheduled, .delayed].contains(session.lifecycle) else { return nil }
        return SportsWatchTarget(id: session.id, title: SportsRaceFormat.watchTitle(weekend, session), live: session.isLive,
                                 kind: "racing", parentID: weekend.id, noun: String(localized: "session"))
    }
}
