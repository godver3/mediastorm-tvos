#if os(iOS)
import SwiftUI

/// Channels as a list (Expo's phone channel list): logo, name, what is on now with its progress
/// and what is next. Tap tunes; swipe right to favorite, left to hide; long-press for recording,
/// Choose Source and the programme's details. More channels load near the end.
struct MobileChannelList: View {
    let now: Date
    @EnvironmentObject private var store: LiveStore

    var body: some View {
        let channels = store.visibleChannels
        List {
            Section {
                ForEach(channels) { channel in
                    MobileChannelRow(channel: channel, now: now)
                        .onAppear {
                            store.needNowNext(channel)
                            if channel.id == channels[max(0, channels.count - 20)].id {
                                Task { await store.loadMore() }
                            }
                        }
                }
                if store.isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                }
            } header: {
                if store.filter != .all || store.sourceID != nil {
                    Text(header)
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await store.reload(force: true) }
    }

    private var header: String {
        var parts = [store.filter.label]
        if let source = store.sources.first(where: { $0.id == store.sourceID }) { parts.append(source.name) }
        if let total = store.total { parts.append(String(localized: "\(total) channels")) }
        return parts.joined(separator: " · ")
    }
}

struct MobileChannelRow: View {
    let channel: LiveChannel
    let now: Date
    @EnvironmentObject private var store: LiveStore
    @ScaledMetric(relativeTo: .body) private var logoWidth: CGFloat = 76

    var body: some View {
        let current = store.current(channel, at: now)
        let next = store.next(channel, at: now)
        Button {
            MobileLiveTune.play(channel, program: current)
        } label: {
            HStack(alignment: .center, spacing: 14) {
                ChannelLogo(channel: channel, size: CGSize(width: logoWidth, height: logoWidth * 9 / 16),
                            font: .caption.weight(.semibold))
                    .frame(width: logoWidth, height: logoWidth * 9 / 16)
                    .padding(4)
                    .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(channel.name).font(.headline).lineLimit(1)
                        if store.favorites.contains(channel.id) {
                            Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                                .accessibilityLabel("Favorite")
                        }
                        if store.hidden.contains(channel.id) {
                            Image(systemName: "eye.slash").font(.caption).foregroundStyle(.secondary)
                                .accessibilityLabel("Hidden")
                        }
                        if let recording = store.recording(on: channel) { LiveRecordingBadge(recording: recording) }
                    }
                    if let current {
                        HStack(spacing: 6) {
                            if current.isNew { NewAiringTag() }
                            Text(current.title).font(.subheadline).lineLimit(1)
                        }
                        ProgressView(value: current.progress(at: now))
                            .tint(.accentColor)
                            .accessibilityHidden(true)
                        if let next {
                            Text("Next: \(next.start, format: .dateTime.hour().minute()) \(next.title)")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    } else if let group = channel.group, !group.isEmpty {
                        Text(group).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("live-channel-\(channel.id)")
        .accessibilityLabel([channel.name, current?.title].compactMap { $0 }.joined(separator: ", "))
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                store.toggleFavorite(channel)
            } label: {
                if store.favorites.contains(channel.id) {
                    Label("Unfavorite", systemImage: "star.slash")
                } else {
                    Label("Favorite", systemImage: "star")
                }
            }
            .tint(.yellow)
        }
        .swipeActions(edge: .trailing) {
            Button {
                store.toggleHidden(channel)
            } label: {
                if store.hidden.contains(channel.id) {
                    Label("Show", systemImage: "eye")
                } else {
                    Label("Hide", systemImage: "eye.slash")
                }
            }
            .tint(.gray)
        }
        .contextMenu {
            MobileLiveChannelMenu(channel: channel, program: nil)
        } preview: {
            MobileLivePreview(channel: channel, program: current, now: now)
        }
    }
}

/// A channel's long-press menu: Watch, Info, Start Over (with catch-up), then the TV's channel
/// menu (recording, Choose Source, favorite and hide).
struct MobileLiveChannelMenu: View {
    let channel: LiveChannel
    /// The guide programme long-pressed; nil on a channel row (what is on now).
    let program: EPGProgram?
    @EnvironmentObject private var store: LiveStore
    @Environment(\.mobileLiveActions) private var actions

    var body: some View {
        let shown = program ?? store.current(channel)
        Button {
            MobileLiveTune.play(channel, program: shown)
        } label: {
            if let shown, shown.stop <= Date() {
                Label("Watch from Start", systemImage: "gobackward")
            } else {
                Label("Watch Live", systemImage: "play.fill")
            }
        }
        if let shown, shown.stop > Date(), channel.canReplay(shown) {
            Button { CatchupPlayback.play(channel, program: shown) } label: {
                Label("Start Over", systemImage: "gobackward")
            }
        }
        Button {
            actions.showInfo(MobileLiveInfoTarget(channel: channel, program: shown))
        } label: {
            Label("Details", systemImage: "info.circle")
        }
        Divider()
        LiveChannelMenu(channel: channel, program: program.flatMap { $0.stop > Date() ? $0 : nil })
    }
}

/// The context menu's preview: the channel, and the programme with its times and description.
struct MobileLivePreview: View {
    let channel: LiveChannel
    let program: EPGProgram?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ChannelLogo(channel: channel, size: CGSize(width: 80, height: 45), font: .caption, namesChannel: false)
                    .frame(width: 80, height: 45)
                Text(channel.name).font(.headline)
            }
            if let program {
                Text(program.title).font(.title3.weight(.semibold))
                Text(GuideTime.range(program.start, program.stop)).font(.subheadline).foregroundStyle(.secondary)
                if program.isAiring(at: now) { ProgressView(value: program.progress(at: now)) }
                if let description = program.description, !description.isEmpty {
                    Text(description).font(.callout).foregroundStyle(.secondary).lineLimit(5)
                }
            }
        }
        .padding()
        .frame(width: 320, alignment: .leading)
    }
}
#endif
