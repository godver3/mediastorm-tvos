import SwiftUI

/// A cycling race's page (Expo `app/sports/cycling/[raceId].tsx` with `SportsCyclingDetailTV`):
/// the header (`SportsCyclingHeader`), then Stage Overview (results beside the overall leaders),
/// Overall GC and Route. A dates-only race shows its published schedule; Hide Scores leaves the
/// stage's facts only. The race loads once on open (and on Try Again), the stage every 5 min.
struct SportsCyclingView: View {
    @StateObject private var model: SportsCyclingPageModel
    @ObservedObject private var spoilers = SportsSpoilers.shared
    @FocusState private var focus: SportsCyclingFocus?
    @State private var watching: SportsWatchTarget?
    @State private var picking = false
    /// The stream picked, tuned once the picker has gone (the player can't present over it).
    @State private var chosen: SportsStreamMatch?

    private static let top = "sports-cycling-top"

    init(ref: SportsCyclingRef, hub: SportsHubStore) {
        _model = StateObject(wrappedValue: SportsCyclingPageModel(raceID: ref.raceID, stageID: ref.stageID, feed: hub.cyclingFeed))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 36) {
                    content {
                        model.show(.overall)
                        focus = .tab(.overall)
                        withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(Self.top, anchor: .top) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CardGridLayout.inset)
                .padding(.top, 20)
                .padding(.bottom, 80)
            }
            // Below the menu's tab pill and clipped there, so the page scrolls away under nothing.
            .padding(.top, 70)
            // Back up in the controls, the title shows again.
            .onChange(of: focus) { _, new in
                guard new != nil else { return }
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(Self.top, anchor: .top) }
            }
        }
        .defaultFocus($focus, initialFocus)
        .task(id: model.retries) { await model.loadRace() }
        .task(id: "\(model.stage?.id ?? "")|\(model.race?.scheduleOnly == true)|\(model.retries)") { await model.pollStage() }
        .fullScreenCover(isPresented: $picking, onDismiss: tuneChosen) {
            if let watching {
                SportsStreamPicker(target: watching) { match in
                    chosen = match
                    picking = false
                }
            }
        }
    }

    /// Find Streams when there is something to find, else the stage picker, else Hide Scores.
    private var initialFocus: SportsCyclingFocus {
        guard let race = model.race else { return .spoilers }
        if model.watchTarget != nil { return .watch }
        return SportsCyclingHeader.choosesStage(race) ? .stage : .spoilers
    }

    @ViewBuilder private func content(viewOverall: @escaping () -> Void) -> some View {
        if let race = model.race {
            SportsCyclingHeader(model: model, race: race, spoilers: spoilers.hidden, focus: $focus) { target in
                watching = target
                picking = true
            }
            .id(Self.top)
            if let stage = model.detail {
                if spoilers.hidden && !race.scheduleOnly {
                    spoilerSummary(race, stage)
                } else {
                    if race.scheduleOnly { scheduleNotice(race) }
                    if model.tab == .route {
                        SportsCyclingRoute(model: model, race: race, stage: stage)
                    } else if !race.scheduleOnly {
                        SportsCyclingResultsView(model: model, race: race, stage: stage, viewOverall: viewOverall)
                    }
                }
            } else {
                Text("No stages are available.").foregroundStyle(.secondary).sportsReadout()
            }
        } else if let missing = model.missing {
            SportsNotice(title: String(localized: "Cycling unavailable"), message: missing, retry: model.retry)
                .padding(.top, 120)
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 260)
        }
    }

    /// A dates-only race (Expo's published-schedule notice): its dates, country and what the feed can't say.
    private func scheduleNotice(_ race: SportsCyclingRace) -> some View {
        let provider = race.source.provider.isEmpty ? String(localized: "Organizer") : race.source.provider
        let lines = [String(localized: "\(SportsCycling.dateRange(race)) · Start time TBC"), race.country,
                     String(localized: "Use Find Streams to search your available sources. Broadcast availability is not confirmed."),
                     String(localized: "\(provider) · Checked \(SportsCycling.date(race.source.observedAt)). Dates may change. Live timing and results are not supplied.")]
        return summaryPanel(race.name, lines: lines.compactMap { $0?.isEmpty == false ? $0 : nil }, last: nil)
    }

    /// Hide Scores (Expo's spoiler view): the race and stage facts, no classification.
    private func spoilerSummary(_ race: SportsCyclingRace, _ stage: SportsCyclingStage) -> some View {
        let facts = [stage.distance, stage.terrain].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
        let lines = [race.country, stage.name, stage.route, facts].compactMap { $0?.isEmpty == false ? $0 : nil }
        return summaryPanel(race.name, lines: lines, last: String(localized: "Stage results and classification hidden"))
    }

    private func summaryPanel(_ title: String, lines: [String], last: String?) -> some View {
        SportsPanel(title) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines, id: \.self) { Text($0).foregroundStyle(.secondary) }
                if let last { Text(last) }
            }
            .sportsReadout()
        }
        .frame(maxWidth: 1100, alignment: .leading)
    }

    private func tuneChosen() {
        guard let match = chosen else { return }
        chosen = nil
        LivePlayback.play(match.channel, program: nil)
    }
}
