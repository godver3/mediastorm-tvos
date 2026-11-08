#if os(iOS)
import SwiftUI

/// A programme's details (the TV guide's info panel and programme menu as a sheet): channel,
/// title, times and progress, episode and description; Watch (live, from catch-up, or Start
/// Over), the recording actions, the channel's favorite / hide / Choose Source, and what airs
/// next on the channel. Anything that opens a player or another sheet is handed back through
/// `perform` and runs once this sheet is gone.
struct MobileLiveProgramSheet: View {
    let target: MobileLiveInfoTarget
    let perform: (@escaping () -> Void) -> Void
    @EnvironmentObject private var store: LiveStore
    @Environment(\.dismiss) private var dismiss

    private var channel: LiveChannel { target.channel }

    var body: some View {
        let now = Date()
        let program = target.program
        NavigationStack {
            List {
                Section { header(program, now: now) }
                Section {
                    watchButtons(program, now: now)
                }
                if program.map({ $0.stop > now }) ?? true {
                    Section("Record") {
                        if let program {
                            LiveProgramRecordMenu(channel: channel, program: program)
                        }
                        LiveChannelRecordMenu(channel: channel, airing: program == nil)
                    }
                }
                Section("Channel") { channelButtons }
                let upcoming = upcoming(after: program, now: now)
                if !upcoming.isEmpty {
                    Section("Later on \(channel.name)") {
                        ForEach(upcoming, id: \.start) { p in
                            LabeledContent {
                                Text(p.start, format: .dateTime.hour().minute())
                            } label: {
                                Text(p.title)
                                if let episode = p.episode, !episode.isEmpty { Text(episode) }
                            }
                        }
                    }
                }
            }
            .navigationTitle(channel.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .overlay(alignment: .bottom) {
                if let notice = store.notice {
                    Text(notice).font(.footnote)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 8)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder private func header(_ program: EPGProgram?, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ChannelLogo(channel: channel, size: CGSize(width: 72, height: 40), font: .caption, namesChannel: false)
                    .frame(width: 72, height: 40)
                VStack(alignment: .leading) {
                    Text(channel.name).font(.subheadline.weight(.semibold))
                    if let group = channel.group, !group.isEmpty {
                        Text(group).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let program {
                Text(program.title).font(.title2.weight(.bold))
                HStack(spacing: 8) {
                    if program.isAiring(at: now) {
                        Text("LIVE").font(.caption2.weight(.heavy))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.red))
                            .foregroundStyle(.white)
                    }
                    if program.isNew { NewAiringTag(prominent: true) }
                    if let recording = store.recording(on: channel, during: program) {
                        Label(recording.status.label, systemImage: "record.circle")
                            .font(.caption.weight(.semibold)).foregroundStyle(.red)
                    }
                    Text(details(program, now: now)).font(.subheadline).foregroundStyle(.secondary)
                }
                if program.isAiring(at: now) {
                    ProgressView(value: program.progress(at: now))
                }
                if let description = program.description, !description.isEmpty {
                    Text(description).font(.body).foregroundStyle(.secondary)
                }
            } else {
                Text("No guide information").foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func watchButtons(_ program: EPGProgram?, now: Date) -> some View {
        let channel = self.channel
        if let program, program.stop <= now {
            if channel.canReplay(program, now: now) {
                Button { perform { CatchupPlayback.play(channel, program: program) } } label: {
                    Label("Watch from Start", systemImage: "gobackward")
                }
            }
            Button { perform { MobileLiveTune.play(channel, program: nil) } } label: {
                Label("Watch \(channel.name) Live", systemImage: "play.fill")
            }
        } else {
            let current = program.flatMap { $0.isAiring(at: now) ? $0 : nil } ?? store.current(channel, at: now)
            Button { perform { LivePlayback.play(channel, program: current) } } label: {
                Label("Watch Live", systemImage: "play.fill")
            }
            .accessibilityIdentifier("live.info.watch")
            if let current, channel.canReplay(current, now: now) {
                Button { perform { CatchupPlayback.play(channel, program: current) } } label: {
                    Label("Start Over", systemImage: "gobackward")
                }
            }
        }
    }

    @ViewBuilder private var channelButtons: some View {
        let channel = self.channel
        let store = self.store
        if channel.hasStremioSources {
            Button { perform { store.chooseSource(channel) } } label: {
                Label("Choose Source", systemImage: "square.stack.3d.up")
            }
        }
        Button {
            store.toggleFavorite(channel)
        } label: {
            if store.favorites.contains(channel.id) {
                Label("Remove from Favorites", systemImage: "star.slash")
            } else {
                Label("Add to Favorites", systemImage: "star")
            }
        }
        Button {
            store.toggleHidden(channel)
        } label: {
            if store.hidden.contains(channel.id) {
                Label("Show Channel", systemImage: "eye")
            } else {
                Label("Hide Channel", systemImage: "eye.slash")
            }
        }
    }

    private func upcoming(after program: EPGProgram?, now: Date) -> [EPGProgram] {
        let from = max(program?.stop ?? now, now)
        let list = store.schedules[channel.guideKey] ?? []
        let later = list.filter { $0.start >= from }.prefix(6)
        if !later.isEmpty || program != nil { return Array(later) }
        return store.next(channel, at: now).map { [$0] } ?? []
    }

    private func details(_ p: EPGProgram, now: Date) -> String {
        var parts = [GuideTime.range(p.start, p.stop)]
        if p.isAiring(at: now) {
            parts.append(String(localized: "\(Int(p.stop.timeIntervalSince(now) / 60)) min left"))
        } else {
            parts.append(p.start.formatted(.relative(presentation: .named)))
        }
        if let ep = p.episode, !ep.isEmpty { parts.append(ep) }
        if p.isRerun && !p.isNew { parts.append(String(localized: "Rerun")) }
        if let cat = p.categories?.first { parts.append(cat) }
        return parts.joined(separator: " · ")
    }
}

/// Choose Source for a Stremio channel: the addon's streams, one of which is then tuned.
struct MobileLiveSourceChoiceSheet: View {
    let choice: LiveSourceChoice
    let onPick: (LiveStremioStream) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(choice.streams) { stream in
                Button { onPick(stream) } label: {
                    Label {
                        Text(stream.label).lineLimit(3)
                    } icon: {
                        Image(systemName: "play.circle")
                    }
                }
                .accessibilityIdentifier("live-source-\(stream.index)")
            }
            .navigationTitle(choice.channel.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
#endif
