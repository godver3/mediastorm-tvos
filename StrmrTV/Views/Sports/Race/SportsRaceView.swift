import SwiftUI

/// A race weekend's page (Expo `app/sports/race/[eventId].tsx` with `SportsRaceDetailTV`): the
/// header (`SportsRaceHeader`), then Overview (the classification's top eight beside the driver
/// card, the comparison and the circuit guide), Timing (every entry, with F1 archive telemetry)
/// or MotoGP's Championship, and F1's session insights under the first two. Hide Scores leaves
/// the schedule and the circuit. The session reloads every 30 s, every 10 min once final.
struct SportsRaceView: View {
    let leagueName: (String) -> String

    @StateObject private var model: SportsRacePageModel
    @ObservedObject private var spoilers = SportsSpoilers.shared
    @FocusState private var focus: SportsRaceFocus?
    @State private var watching: SportsWatchTarget?
    @State private var picking = false
    /// The stream picked, tuned once the picker has gone (the player can't present over it).
    @State private var chosen: SportsStreamMatch?

    private static let top = "sports-race-top"

    init(ref: SportsRaceRef, board: SportsRaceBoard?, leagueName: @escaping (String) -> String) {
        self.leagueName = leagueName
        _model = StateObject(wrappedValue: SportsRacePageModel(weekendID: ref.weekendID, sessionID: ref.sessionID, board: board))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 36) {
                    content { withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(Self.top, anchor: .top) } }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CardGridLayout.inset)
                .padding(.top, 20)
                .padding(.bottom, 80)
            }
            // Back up in the controls, the title shows again.
            .onChange(of: focus) { _, new in
                guard new != nil else { return }
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(Self.top, anchor: .top) }
            }
        }
        .defaultFocus($focus, initialFocus)
        .task(id: model.retries) { await model.loadWeekend() }
        .task(id: "\(model.session?.id ?? "")|\(model.retries)|\(championship)") {
            if !championship { await model.pollSession() }
        }
        .task(id: "\(model.detail?.id ?? "")|\(model.detail?.status ?? "")") { await model.loadArchive() }
        .task(id: "\(model.weekend?.id ?? "")|\(model.retries)") { await model.loadGuide() }
        .task(id: "\(championship)|\(model.retries)") {
            if championship { await model.pollStandings() }
        }
        .fullScreenCover(isPresented: $picking, onDismiss: tuneChosen) {
            if let watching {
                SportsStreamPicker(target: watching) { match in
                    chosen = match
                    picking = false
                }
            }
        }
    }

    private var championship: Bool { model.tab == .championship }

    @ViewBuilder private func content(scrollUp: @escaping () -> Void) -> some View {
        if let weekend = model.weekend {
            SportsRaceHeader(model: model, weekend: weekend, leagueName: leagueName(weekend.league), spoilers: spoilers.hidden,
                             focus: $focus) { target in
                watching = target
                picking = true
            }
            // Clear of the menu's tab pill, also when scrolled back to the top.
            .padding(.top, 70)
            .id(Self.top)
            if spoilers.hidden {
                spoilerSummary(weekend)
            } else if championship {
                SportsMotoGPStandingsView(standings: model.standings, failed: model.standingsFailed, retry: model.retry)
            } else if model.tab == .timing {
                SportsRaceSessionResults(model: model, overview: false)
            } else {
                overview(weekend) {
                    model.tab = .timing
                    focus = .tab(.timing)
                    scrollUp()
                }
            }
            if !spoilers.hidden, !championship, let archive = model.timingArchive {
                SportsF1Insights(archive: archive, driverNumber: model.competitor.map { $0.number ?? $0.id })
                    .id(archive.eventId)
            }
        } else if let missing = model.missing {
            SportsNotice(title: String(localized: "Race weekend unavailable"), message: missing, retry: model.retry)
                .padding(.top, 120)
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 260)
        }
    }

    /// Watch when there is something to watch, else the session picker, else Hide Scores.
    private var initialFocus: SportsRaceFocus {
        guard let weekend = model.weekend, let session = model.detail else { return .spoilers }
        if SportsRaceHeader.watchTarget(weekend, session) != nil { return .watch }
        return weekend.sessions.count > 1 ? .session : .spoilers
    }

    /// Overview: the session's results beside the selected entry's card, the comparison and the
    /// circuit; the results take the width when there is none of those (entries not out yet,
    /// no circuit guide).
    @ViewBuilder private func overview(_ weekend: SportsRaceEvent, viewAll: @escaping () -> Void) -> some View {
        let results = SportsRaceSessionResults(model: model, overview: true, viewAll: viewAll)
        if model.competitor == nil && weekend.circuit == nil && !weekend.riders {
            results
        } else {
            SportsColumns(weights: [1.2, 1]) {
                results.frame(maxHeight: .infinity, alignment: .top).focusSection()
                VStack(alignment: .leading, spacing: 24) {
                    if let detail = model.detail, let competitor = model.competitor {
                        SportsRaceDriverCard(driver: competitor).id(competitor.id)
                        SportsRaceComparison(drivers: detail.participants, selected: competitor, session: detail)
                            .id(detail.id)
                    }
                    circuitGuide(weekend)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .focusSection()
            }
        }
    }

    /// F1's reference outline when the weekend has one, else MotoGP's organizer guide.
    @ViewBuilder private func circuitGuide(_ weekend: SportsRaceEvent) -> some View {
        if let circuit = weekend.circuit {
            SportsCircuitMap(circuit: circuit)
        } else if weekend.riders {
            SportsMotoGPGuide(guide: model.guide, failed: model.guideFailed,
                              venue: weekend.venue ?? weekend.subEvents.lazy.compactMap(\.venue).first, retry: model.retry)
        }
    }

    /// Hide Scores: what was known before the start (Expo's spoiler view: place, time and where
    /// it's on, the shown session's channels first), then the circuit.
    private func spoilerSummary(_ weekend: SportsRaceEvent) -> some View {
        let broadcasts = model.detail?.broadcasts.flatMap { $0.isEmpty ? nil : $0 } ?? weekend.broadcasts ?? []
        let lines = [(model.detail ?? weekend).place(weekend), weekend.start.map { SportsRaceFormat.date($0) },
                     broadcasts.isEmpty ? nil : broadcasts.joined(separator: " · ")].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 24) {
            SportsPanel(weekend.title.trimmingCharacters(in: .whitespaces)) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(lines, id: \.self) { Text($0).foregroundStyle(.secondary) }
                    Text("Session timing and results hidden")
                }
                .sportsReadout()
            }
            circuitGuide(weekend).frame(maxWidth: 900, alignment: .leading)
        }
    }

    private func tuneChosen() {
        guard let match = chosen else { return }
        chosen = nil
        LivePlayback.play(match.channel, program: nil)
    }
}
