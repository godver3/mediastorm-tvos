#if os(iOS)
import SwiftUI

/// The phone guide (Expo's mobile `EPGGrid`): a time grid that scrolls sideways under a time
/// ruler, with the channel column pinned on the left and a line at the current time. On a phone
/// about an hour and a half fits across (three hours on a wide screen); it runs from what the
/// provider's catch-up still holds (else half an hour ago) to a day ahead. Tap a programme to
/// watch it (an ended one replays from catch-up, a later one opens its details), long-press for
/// recording, favorite and hide. Guide data loads in chunks for the rows and hours on screen.
struct MobileGuideView: View {
    let now: Date
    @EnvironmentObject private var store: LiveStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The grid's left edge in time, fixed when the guide appears.
    @State private var start = LiveStore.halfHour(Date()).addingTimeInterval(-1800)
    @State private var position = ScrollPosition(edge: .leading)
    @State private var offsetX: CGFloat = 0
    @State private var width: CGFloat = 0
    @State private var placed = false
    /// Rows on screen, kept out of view state so scrolling doesn't redraw the guide.
    @State private var onScreen = OnScreen()

    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 62
    static let rulerHeight: CGFloat = 30

    private var compact: Bool { sizeClass == .compact }
    var channelWidth: CGFloat { compact ? 92 : 190 }
    private var end: Date { LiveStore.halfHour(now).addingTimeInterval(24 * 3600) }
    /// Points per second of airtime.
    private var scale: CGFloat {
        let visible: TimeInterval = compact && width < 600 ? 5400 : 3 * 3600
        return max(width - channelWidth, 200) / visible
    }
    /// The time at the left edge of the programme area, and the stretch on screen.
    private var leadingTime: Date { start.addingTimeInterval(max(0, offsetX) / scale) }
    private var visibleSpan: TimeInterval { max(width - channelWidth, 200) / scale }
    /// Cells are laid out for the hours around the screen, by the half hour, not the whole day.
    private var window: (from: Date, to: Date) {
        let from = max(start, LiveStore.halfHour(leadingTime).addingTimeInterval(-5400))
        return (from, min(end, from.addingTimeInterval(visibleSpan + 4 * 3600)))
    }

    var body: some View {
        let channels = store.visibleChannels
        let window = self.window
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                ruler
                Divider()
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(channels) { channel in
                            MobileGuideRow(channel: channel, cells: cells(for: channel, window), start: start, scale: scale,
                                           now: now, channelWidth: channelWidth, offsetX: max(0, offsetX), compact: compact)
                                .frame(height: rowHeight)
                                .onAppear {
                                    onScreen.ids.insert(channel.id)
                                    store.needSchedule(channel, from: leadingTime, to: leadingTime.addingTimeInterval(visibleSpan))
                                    if channel.id == channels[max(0, channels.count - 20)].id {
                                        Task { await store.loadMore() }
                                    }
                                }
                                .onDisappear { onScreen.ids.remove(channel.id) }
                            Divider()
                        }
                    }
                    .background(alignment: .topLeading) { nowLine }
                }
                .scrollIndicators(.hidden)
                .refreshable { await store.reload(force: true) }
            }
            .frame(width: channelWidth + end.timeIntervalSince(start) * scale, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .scrollPosition($position)
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x }) { _, x in offsetX = x }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { new in
            let anchor = placed ? leadingTime : nil
            width = new
            scroll(to: anchor)
        }
        .onAppear {
            start = LiveStore.halfHour(Date()).addingTimeInterval(-min(max(store.guideHistory, 1800), 24 * 3600))
        }
        .onChange(of: LiveStore.halfHour(leadingTime)) { loadVisible(channels) }
        // On the ruler's right end, so it covers no programmes.
        .overlay(alignment: .topTrailing) { timeButtons }
    }

    // MARK: Scrolling

    /// Puts `time` (by default half an hour before now's half hour) at the left edge.
    private func scroll(to time: Date? = nil) {
        guard width > 0 else { return }
        let target = time ?? LiveStore.halfHour(Date()).addingTimeInterval(-900)
        position.scrollTo(x: max(0, target.timeIntervalSince(start) * scale))
        placed = true
    }

    private func loadVisible(_ channels: [LiveChannel]) {
        for channel in channels where onScreen.ids.contains(channel.id) {
            store.needSchedule(channel, from: leadingTime, to: leadingTime.addingTimeInterval(visibleSpan))
        }
    }

    /// Back an hour, Now, and on an hour (Expo's guide nav buttons).
    private var timeButtons: some View {
        HStack(spacing: 2) {
            Button { withAnimation { scroll(to: leadingTime.addingTimeInterval(-3600)) } } label: {
                Image(systemName: "chevron.left").frame(width: 30, height: 26)
            }
            .accessibilityLabel("Earlier")
            Button { withAnimation { scroll() } } label: {
                Text("Now").padding(.horizontal, 4).frame(height: 26)
            }
            .accessibilityIdentifier("guide.now")
            Button { withAnimation { scroll(to: leadingTime.addingTimeInterval(3600)) } } label: {
                Image(systemName: "chevron.right").frame(width: 30, height: 26)
            }
            .accessibilityLabel("Later")
        }
        .font(.footnote.weight(.semibold))
        .background(.regularMaterial, in: Capsule())
        .padding(.trailing, 8)
        .frame(height: Self.rulerHeight)
    }

    // MARK: Ruler and now line

    private var ruler: some View {
        HStack(spacing: 0) {
            ForEach(0..<Int(end.timeIntervalSince(start) / 1800), id: \.self) { i in
                let time = start.addingTimeInterval(Double(i) * 1800)
                Text(Self.rulerLabel(time))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
                    .frame(width: 1800 * scale, alignment: .leading)
                    .overlay(alignment: .leading) { Rectangle().fill(.quaternary).frame(width: 1, height: 10) }
            }
        }
        .padding(.leading, channelWidth)
        .frame(height: Self.rulerHeight)
        .overlay(alignment: .leading) {
            // The corner over the channel column: the day the left edge is on.
            Text(leadingTime, format: .dateTime.weekday(.abbreviated).day())
                .font(.caption.weight(.bold))
                .frame(width: channelWidth, height: Self.rulerHeight)
                .background(.background)
                .offset(x: max(0, offsetX))
        }
    }

    /// "21:30"; midnight names the day it starts.
    private static func rulerLabel(_ time: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        guard parts.hour == 0, parts.minute == 0 else { return time.formatted(.dateTime.hour().minute()) }
        return time.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    @ViewBuilder private var nowLine: some View {
        if now >= start, now < end {
            Rectangle()
                .fill(LiveGuideView.nowLineColor)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .offset(x: channelWidth + now.timeIntervalSince(start) * scale - 1)
                .allowsHitTesting(false)
        }
    }

    private func cells(for channel: LiveChannel, _ window: (from: Date, to: Date)) -> [GuideCell] {
        GuideCell.layout(channel: channel.id, programs: store.schedules[channel.guideKey] ?? [],
                         from: window.from, to: window.to)
    }

    final class OnScreen {
        var ids = Set<String>()
    }
}

/// One channel's row: its programmes placed by time, under the pinned channel cell.
private struct MobileGuideRow: View {
    let channel: LiveChannel
    let cells: [GuideCell]
    let start: Date
    let scale: CGFloat
    let now: Date
    let channelWidth: CGFloat
    /// The grid's sideways scroll, which the channel cell follows to stay at the left edge.
    let offsetX: CGFloat
    let compact: Bool
    @EnvironmentObject private var store: LiveStore
    @Environment(\.mobileLiveActions) private var actions
    @Environment(\.mobileLiveMenuOpen) private var menuOpen

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Cells are cut at the channel column rather than drawn under it: whatever covered
            // them there (the channel cell, hidden by UIKit while its long-press menu is open)
            // let the programme's colour show through beside the logo.
            ForEach(cells) { cell in
                let x = cell.start.timeIntervalSince(start) * scale
                let end = x + max(cell.end.timeIntervalSince(cell.start) * scale - 2, 4)
                let left = max(x, offsetX)
                if end - left >= 4 {
                    MobileGuideCell(channel: channel, cell: cell, now: now,
                                    recording: cell.program.flatMap { store.recording(on: channel, during: $0) },
                                    continued: left > x)
                        .frame(width: end - left)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, 3)
                        .offset(x: channelWidth + left + 1)
                }
            }
            channelCell
                .offset(x: offsetX)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var channelCell: some View {
        Button {
            MobileLiveTune.play(channel, program: store.current(channel, at: now))
        } label: {
            HStack(spacing: 8) {
                ChannelLogo(channel: channel, size: CGSize(width: 64, height: 36), font: .caption2.weight(.semibold))
                    .frame(width: 64, height: 36)
                    .hiddenUnderLiveMenu(menuOpen)
                if !compact {
                    Text(channel.name).font(.footnote.weight(.semibold)).lineLimit(2)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 8)
            .frame(width: channelWidth)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                if store.favorites.contains(channel.id) {
                    Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow).padding(4)
                }
            }
            .background(.background)
            .overlay(alignment: .trailing) { Rectangle().fill(.separator).frame(width: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(channel.name)
        .accessibilityIdentifier("guide-channel-\(channel.id)")
        .contextMenu {
            MobileLiveChannelMenu(channel: channel, program: nil)
        } preview: {
            MobileLivePreview(channel: channel, program: store.current(channel, at: now), now: now, onPresented: actions.menuOpened)
        }
    }
}

private struct MobileGuideCell: View {
    let channel: LiveChannel
    let cell: GuideCell
    let now: Date
    let recording: Recording?
    /// Cut at the channel column: the programme runs on to the left.
    let continued: Bool
    @Environment(\.mobileLiveActions) private var actions

    private var airing: Bool { cell.program?.isAiring(at: now) == true }

    var body: some View {
        Button {
            guard let program = cell.program else { return MobileLiveTune.play(channel, program: nil) }
            // A later programme has nothing to play yet: its details offer recording.
            if program.start > Date() {
                actions.showInfo(MobileLiveInfoTarget(channel: channel, program: program))
            } else {
                MobileLiveTune.play(channel, program: program)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if continued || cell.program.map({ $0.start < cell.start }) == true {
                        Image(systemName: "chevron.left").font(.caption2.weight(.bold))
                    }
                    if let recording { LiveRecordingBadge(recording: recording) }
                    if cell.program?.isNew == true { NewAiringTag() }
                    Text(cell.program?.title ?? String(localized: "No Information"))
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                }
                if let p = cell.program {
                    Text(GuideTime.range(p.start, p.stop)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(airing ? Color.accentColor.opacity(0.22) : Color(white: 1, opacity: cell.program == nil ? 0.04 : 0.09)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(cell.program?.stop ?? .distantFuture <= now ? .secondary : .primary)
        .accessibilityLabel([channel.name, cell.program?.title].compactMap { $0 }.joined(separator: ", "))
        .contextMenu {
            if let program = cell.program {
                MobileLiveChannelMenu(channel: channel, program: program)
            } else {
                MobileLiveChannelMenu(channel: channel, program: nil)
            }
        } preview: {
            MobileLivePreview(channel: channel, program: cell.program, now: now, onPresented: actions.menuOpened)
        }
    }
}
#endif
