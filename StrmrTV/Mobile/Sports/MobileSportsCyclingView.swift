#if os(iOS)
import SwiftUI

/// A cycling race's page on a phone (Expo `app/sports/cycling/[raceId].tsx`): "CYCLING", the
/// race, the stage's line and state, Find Streams (the stream picker sheet) and the stage menu,
/// then Stage Overview / Overall GC / Route as a segmented control over the TV's panels
/// (`SportsCyclingPageModel`, `SportsCyclingResultsView`, `SportsCyclingRoute`), stacked on a
/// narrow screen. A dates-only race shows its published schedule; Hide Scores leaves the stage's
/// facts only.
struct MobileSportsCyclingView: View {
    @StateObject private var model: SportsCyclingPageModel
    @ObservedObject private var spoilers = SportsSpoilers.shared
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var watching: SportsWatchTarget?
    @State private var chosen: SportsStreamMatch?

    init(ref: SportsCyclingRef, hub: SportsHubStore) {
        _model = StateObject(wrappedValue: SportsCyclingPageModel(raceID: ref.raceID, stageID: ref.stageID, feed: hub.cyclingFeed))
    }

    var body: some View {
        MobileSportsScroll {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .environment(\.sportsStacksColumns, sizeClass == .compact)
        .navigationTitle(model.race?.name ?? String(localized: "Cycling"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { MobileSportsSpoilerToolbar() }
        .refreshable { model.retry() }
        .task(id: model.retries) { await model.loadRace() }
        .task(id: "\(model.stage?.id ?? "")|\(model.race?.scheduleOnly == true)|\(model.retries)") { await model.pollStage() }
        .sheet(item: $watching, onDismiss: tuneChosen) { target in
            MobileSportsStreamPicker(target: target) { match in
                chosen = match
                watching = nil
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let race = model.race {
            header(race)
            if let stage = model.detail {
                if spoilers.hidden && !race.scheduleOnly {
                    summary(race.name, lines: [race.country, stage.name, stage.route, facts(stage)],
                            last: String(localized: "Stage results and classification hidden"))
                } else {
                    if model.tabs.count > 1 {
                        MobileSportsTabBar(tabs: model.tabs, label: { $0.label(race) },
                                           selection: Binding(get: { model.tab }, set: { model.show($0) }))
                    }
                    if race.scheduleOnly { scheduleNotice(race) }
                    if model.tab == .route {
                        SportsCyclingRoute(model: model, race: race, stage: stage)
                    } else if !race.scheduleOnly {
                        SportsCyclingResultsView(model: model, race: race, stage: stage) { model.show(.overall) }
                    }
                }
            } else {
                ContentUnavailableView("No Stages", systemImage: "bicycle", description: Text("No stages are available."))
            }
        } else if let missing = model.missing {
            ContentUnavailableView {
                Label("Cycling Unavailable", systemImage: "bicycle")
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

    private func header(_ race: SportsCyclingRace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text([String(localized: "CYCLING"), race.captured ? String(localized: "RECORDED") : nil,
                  model.delayed ? String(localized: "UPDATES DELAYED") : nil].compactMap { $0 }.joined(separator: " · "))
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(race.name).font(.title2.weight(.bold))
            if let stage = model.detail {
                Text(SportsCyclingFormat.stageLine(stage)).font(.subheadline).foregroundStyle(.secondary)
                if !spoilers.hidden {
                    Text(SportsCyclingFormat.stageState(race, stage, model.classification))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(SportsStatusPill.accent)
                }
            }
            HStack(spacing: 10) {
                if let target = model.watchTarget {
                    Button { watching = target } label: {
                        Label("Find Streams", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("sports-cycling-watch")
                }
                if SportsCyclingHeader.choosesStage(race) {
                    let noun = race.championship ? String(localized: "Race") : String(localized: "Stage")
                    Menu {
                        Picker(noun, selection: Binding(get: { model.stage?.id ?? "" }, set: { model.select($0) })) {
                            ForEach(race.stages) { Text(SportsCyclingFormat.stageOption($0)).tag($0.id) }
                        }
                    } label: {
                        Label(model.stage?.name ?? noun, systemImage: "list.bullet")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("sports-cycling-stage")
                }
            }
            .controlSize(.large)
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func facts(_ stage: SportsCyclingStage) -> String? {
        let text = [stage.distance, stage.terrain].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }

    /// A dates-only race: its dates, country and what the feed can't say.
    private func scheduleNotice(_ race: SportsCyclingRace) -> some View {
        let provider = race.source.provider.isEmpty ? String(localized: "Organizer") : race.source.provider
        return summary(race.name, lines: [String(localized: "\(SportsCycling.dateRange(race)) · Start time TBC"), race.country,
                                          String(localized: "Use Find Streams to search your available sources. Broadcast availability is not confirmed."),
                                          String(localized: "\(provider) · Checked \(SportsCycling.date(race.source.observedAt)). Dates may change.")],
                       last: nil)
    }

    private func summary(_ title: String, lines: [String?], last: String?) -> some View {
        SportsPanel(title) {
            ForEach(lines.compactMap { $0?.isEmpty == false ? $0 : nil }, id: \.self) { Text($0).foregroundStyle(.secondary) }
            if let last { Text(last) }
        }
    }

    private func tuneChosen() {
        guard let match = chosen else { return }
        chosen = nil
        LivePlayback.play(match.channel, program: nil)
    }
}
#endif
