#if os(iOS)
import SwiftUI

/// A race weekend's page on a phone (Expo `app/sports/race/[eventId].tsx`): series and state, the
/// weekend's title and the shown session's line, Watch Live / Find Streams (the stream picker
/// sheet), the session menu, then Overview / Timing (/ MotoGP's Championship) as a segmented
/// control over the TV's panels (`SportsRacePageModel` and its views), stacked on a narrow
/// screen, with F1's session insights under them. Hide Scores leaves the schedule and the
/// circuit.
struct MobileSportsRaceView: View {
    @ObservedObject var hub: SportsHubStore
    @StateObject private var model: SportsRacePageModel
    @ObservedObject private var spoilers = SportsSpoilers.shared
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var watching: SportsWatchTarget?
    @State private var chosen: SportsStreamMatch?

    init(ref: SportsRaceRef, hub: SportsHubStore) {
        self.hub = hub
        _model = StateObject(wrappedValue: SportsRacePageModel(weekendID: ref.weekendID, sessionID: ref.sessionID, board: hub.raceBoard))
    }

    private var championship: Bool { model.tab == .championship }

    var body: some View {
        MobileSportsScroll {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .environment(\.sportsStacksColumns, sizeClass == .compact)
        .navigationTitle(model.weekend.map { SportsRaceFormat.cardTitle($0.title) } ?? String(localized: "Race"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { MobileSportsSpoilerToolbar() }
        .refreshable { model.retry() }
        .task(id: model.retries) { await model.loadWeekend() }
        .task(id: "\(model.session?.id ?? "")|\(model.retries)|\(championship)") {
            if !championship { await model.pollSession() }
        }
        .task(id: "\(model.detail?.id ?? "")|\(model.detail?.status ?? "")") { await model.loadArchive() }
        .task(id: "\(model.weekend?.id ?? "")|\(model.retries)") { await model.loadGuide() }
        .task(id: "\(championship)|\(model.retries)") {
            if championship { await model.pollStandings() }
        }
        .sheet(item: $watching, onDismiss: tuneChosen) { target in
            MobileSportsStreamPicker(target: target) { match in
                chosen = match
                watching = nil
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let weekend = model.weekend {
            header(weekend)
            if spoilers.hidden {
                spoilerSummary(weekend)
            } else {
                if model.tabs.count > 1 {
                    MobileSportsTabBar(tabs: model.tabs, label: \.label, selection: $model.tab)
                }
                if championship {
                    SportsMotoGPStandingsView(standings: model.standings, failed: model.standingsFailed, retry: model.retry)
                } else if model.tab == .timing {
                    SportsRaceSessionResults(model: model, overview: false)
                } else {
                    SportsRaceSessionResults(model: model, overview: true) { model.tab = .timing }
                    if let detail = model.detail, let competitor = model.competitor {
                        SportsRaceDriverCard(driver: competitor).id(competitor.id)
                        SportsRaceComparison(drivers: detail.participants, selected: competitor, session: detail).id(detail.id)
                    }
                    circuitGuide(weekend)
                }
                if !championship, let archive = model.timingArchive {
                    SportsF1Insights(archive: archive, driverNumber: model.competitor.map { $0.number ?? $0.id }).id(archive.eventId)
                }
            }
        } else if let missing = model.missing {
            ContentUnavailableView {
                Label("Race Weekend Unavailable", systemImage: "flag.checkered")
            } description: {
                Text(missing)
            } actions: {
                Button("Try Again", action: model.retry).buttonStyle(.bordered)
            }
            .padding(.top, 60)
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 120)
        }
    }

    private func header(_ weekend: SportsRaceEvent) -> some View {
        let session = model.detail
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(hub.leagueName(weekend.league).uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let session { SportsStatusPill(lifecycle: session.lifecycle) }
            }
            Text(weekend.title.trimmingCharacters(in: .whitespaces)).font(.title2.weight(.bold))
            Text(championship && !spoilers.hidden ? String(localized: "Championship standings")
                 : session.map { SportsRaceFormat.contextLine($0, weekend: weekend) } ?? String(localized: "Race weekend"))
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if let target = session.flatMap({ SportsRaceHeader.watchTarget(weekend, $0) }) {
                    Button { watching = target } label: {
                        Label(target.live ? "Watch Live" : "Find Streams", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(target.live ? SportsStatusPill.live : .accentColor)
                    .accessibilityIdentifier("sports-race-watch")
                }
                if weekend.sessions.count > 1 {
                    Menu {
                        Picker("Session", selection: Binding(get: { model.session?.id ?? "" }, set: { model.select($0) })) {
                            ForEach(weekend.sessions) { Text(SportsRaceFormat.sessionOption($0)).tag($0.id) }
                        }
                    } label: {
                        Label(session?.sessionType ?? String(localized: "Session"), systemImage: "list.bullet")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("sports-race-session")
                }
            }
            .controlSize(.large)
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    @ViewBuilder private func circuitGuide(_ weekend: SportsRaceEvent) -> some View {
        if let circuit = weekend.circuit {
            SportsCircuitMap(circuit: circuit)
        } else if weekend.riders {
            SportsMotoGPGuide(guide: model.guide, failed: model.guideFailed,
                              venue: weekend.venue ?? weekend.subEvents.lazy.compactMap(\.venue).first, retry: model.retry)
        }
    }

    /// Hide Scores: place, time and channels, then the circuit.
    private func spoilerSummary(_ weekend: SportsRaceEvent) -> some View {
        let broadcasts = model.detail?.broadcasts.flatMap { $0.isEmpty ? nil : $0 } ?? weekend.broadcasts ?? []
        let lines = [(model.detail ?? weekend).place(weekend), weekend.start.map { SportsRaceFormat.date($0) },
                     broadcasts.isEmpty ? nil : broadcasts.joined(separator: " · ")].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 16) {
            SportsPanel(weekend.title.trimmingCharacters(in: .whitespaces)) {
                ForEach(lines, id: \.self) { Text($0).foregroundStyle(.secondary) }
                Text("Session timing and results hidden")
            }
            circuitGuide(weekend)
        }
    }

    private func tuneChosen() {
        guard let match = chosen else { return }
        chosen = nil
        LivePlayback.play(match.channel, program: nil)
    }
}

/// Hide / Show Scores in a sports page's navigation bar.
struct MobileSportsSpoilerToolbar: ToolbarContent {
    @ObservedObject private var spoilers = SportsSpoilers.shared

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { spoilers.hidden.toggle() } label: {
                Label(spoilers.hidden ? "Show Scores" : "Hide Scores", systemImage: spoilers.hidden ? "eye.slash" : "eye")
            }
            .accessibilityIdentifier("sports-spoilers")
        }
    }
}

extension SportsWatchTarget: Identifiable {}
#endif
