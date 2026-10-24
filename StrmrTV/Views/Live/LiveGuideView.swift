import SwiftUI

/// The channel guide: a two-hour window of programmes per channel under an info panel for
/// the focused one. The window pages by half an hour when focus runs off either end of a
/// row (as the Apple TV app's guide does), from half an hour ago to a day ahead; up and
/// down scroll the channels, and more load near the end. Select plays the channel, long
/// press offers favorite / hide. Menu moves focus up to the category picker (see
/// `LiveContentFocus`).
struct LiveGuideView: View {
    let now: Date
    @Binding var request: LiveContentFocus?
    let onExit: () -> Void
    @EnvironmentObject private var store: LiveStore

    @State private var windowStart = LiveStore.halfHour(Date())
    @FocusState private var focus: GuideCellID?
    @State private var width: CGFloat = 0
    /// Rows on screen, kept out of view state so scrolling doesn't redraw the guide.
    @State private var onScreen = OnScreen()

    static let span: TimeInterval = 2 * 3600
    static let step: TimeInterval = 1800
    static let channelWidth: CGFloat = 300
    static let rowHeight: CGFloat = 80
    static let rowSpacing: CGFloat = 10

    private var windowEnd: Date { windowStart.addingTimeInterval(Self.span) }
    /// Points per second of airtime.
    private var scale: CGFloat {
        max(width - CardGridLayout.inset * 2 - Self.channelWidth, 400) / Self.span
    }
    private var earliest: Date { LiveStore.halfHour(now).addingTimeInterval(-Self.step) }
    private var latest: Date { LiveStore.halfHour(now).addingTimeInterval(24 * 3600) }

    var body: some View {
        let channels = store.visibleChannels
        // Up on the controls (after Menu), the panel keeps the cell focus left.
        let shown = focus ?? (store.focusMemory as? GuideCellID)
        let focused = shown.flatMap { id in channels.first { $0.id == id.channel } }
        VStack(alignment: .leading, spacing: 0) {
            GuideInfoPanel(channel: focused ?? channels.first, program: focused.flatMap { program(for: shown!, in: $0) },
                           now: now)
                .frame(height: 190, alignment: .top)
                .padding(.horizontal, CardGridLayout.inset)
            TimeRuler(windowStart: windowStart, scale: scale, now: now)
                .padding(.leading, CardGridLayout.inset + Self.channelWidth)
                .padding(.bottom, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Self.rowSpacing) {
                    ForEach(channels) { channel in
                        GuideRow(channel: channel, cells: cells(for: channel), scale: scale, now: now,
                                 isFavorite: store.favorites.contains(channel.id), focus: $focus)
                            .id(channel.id)
                            .onAppear {
                                onScreen.ids.insert(channel.id)
                                store.needSchedule(channel, from: windowStart, to: windowEnd)
                                if channel.id == channels[max(0, channels.count - 20)].id {
                                    Task { await store.loadMore() }
                                }
                            }
                            .onDisappear { onScreen.ids.remove(channel.id) }
                    }
                }
                .padding(.horizontal, CardGridLayout.inset)
                .padding(.vertical, 12)
            }
            .scrollClipDisabled(false)
            .background(alignment: .topLeading) { nowLine }
            .onMoveCommand(perform: move)
            .liveContentFocus($focus, request: $request, memory: $store.focusMemory, match: match, onExit: onExit)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: windowStart) {
            for channel in channels where onScreen.ids.contains(channel.id) {
                store.needSchedule(channel, from: windowStart, to: windowEnd)
            }
        }
    }

    /// Behind the cells: the unfocused ones are translucent, the focused one covers it.
    @ViewBuilder private var nowLine: some View {
        if now >= windowStart, now < windowEnd {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 3)
                .offset(x: CardGridLayout.inset + Self.channelWidth + now.timeIntervalSince(windowStart) * scale - 1.5)
                .allowsHitTesting(false)
        }
    }

    // MARK: Cells

    private func cells(for channel: LiveChannel) -> [GuideCell] {
        GuideCell.layout(channel: channel.id, programs: store.schedules[channel.guideKey] ?? [],
                         from: windowStart, to: windowEnd)
    }

    /// A remembered cell in the guide as it is now: the same cell, or (its programme gone)
    /// the channel's cell at that time, else what airs now. Nil once the channel is gone.
    private func match(_ id: GuideCellID) -> GuideCellID? {
        guard let channel = store.visibleChannels.first(where: { $0.id == id.channel }) else { return nil }
        let row = cells(for: channel)
        if row.contains(where: { $0.id == id }) { return id }
        let at = row.first { $0.start <= id.start && id.start < $0.end }
            ?? row.first { $0.start <= now && now < $0.end } ?? row.first
        return at?.id
    }

    private func program(for id: GuideCellID, in channel: LiveChannel) -> EPGProgram? {
        cells(for: channel).first { $0.id == id }?.program
    }

    /// Pages the window when focus is on the first / last cell of its row and the press
    /// points off the row, then keeps focus on the programme at the time it moved to.
    private func move(_ direction: MoveCommandDirection) {
        guard let id = focus, let channel = store.visibleChannels.first(where: { $0.id == id.channel }),
              let cell = cells(for: channel).first(where: { $0.id == id }) else { return }
        let target: Date
        switch direction {
        case .right where cell.end >= windowEnd && windowStart < latest:
            target = windowEnd
            windowStart = windowStart.addingTimeInterval(Self.step)
        case .left where cell.start <= windowStart && windowStart > earliest:
            target = windowStart.addingTimeInterval(-1)
            windowStart = windowStart.addingTimeInterval(-Self.step)
        default:
            return
        }
        let next = cells(for: channel).first { $0.start <= target && target < $0.end }
        if let next, next.id != id {
            Task { @MainActor in focus = next.id }
        }
    }

    final class OnScreen {
        var ids = Set<String>()
    }
}

struct GuideCellID: Hashable {
    let channel: String
    /// The programme's own start (stable while the window pages), or a gap's start.
    let start: Date
}

/// One focusable slot in a guide row: a programme, or a stretch without guide data.
struct GuideCell: Identifiable {
    let id: GuideCellID
    let program: EPGProgram?
    /// Clipped to the window.
    let start: Date
    let end: Date

    /// The window's programmes, with gaps filled; gaps under five minutes are folded into
    /// the next programme so no sliver of a cell is left to focus.
    static func layout(channel: String, programs: [EPGProgram], from: Date, to: Date) -> [GuideCell] {
        var cells: [GuideCell] = []
        var cursor = from
        for p in programs where p.stop > cursor && p.start < to {
            var start = max(p.start, cursor)
            if start.timeIntervalSince(cursor) >= 300 {
                cells.append(GuideCell(id: GuideCellID(channel: channel, start: cursor), program: nil, start: cursor, end: start))
            } else {
                start = cursor
            }
            let end = min(p.stop, to)
            cells.append(GuideCell(id: GuideCellID(channel: channel, start: p.start), program: p, start: start, end: end))
            cursor = end
        }
        if to.timeIntervalSince(cursor) >= 60 || cells.isEmpty {
            cells.append(GuideCell(id: GuideCellID(channel: channel, start: cursor), program: nil, start: cursor, end: to))
        } else if let last = cells.popLast() {
            cells.append(GuideCell(id: last.id, program: last.program, start: last.start, end: to))
        }
        return cells
    }
}

private struct GuideRow: View {
    let channel: LiveChannel
    let cells: [GuideCell]
    let scale: CGFloat
    let now: Date
    let isFavorite: Bool
    var focus: FocusState<GuideCellID?>.Binding
    @Environment(\.liveChannelPick) private var pick
    @Environment(\.livePlayingChannelID) private var playingID

    private static let gap: CGFloat = 8

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 16) {
                ChannelLogo(channel: channel, size: CGSize(width: 100, height: 56), font: .title3, namesChannel: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.name).font(.caption.weight(.semibold)).lineLimit(2)
                    HStack(spacing: 8) {
                        if playingID == channel.id {
                            Image(systemName: "play.fill").font(.caption2).foregroundStyle(Color.accentColor)
                        }
                        if isFavorite {
                            Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.trailing, 16)
            .frame(width: LiveGuideView.channelWidth, height: LiveGuideView.rowHeight)

            HStack(spacing: Self.gap) {
                ForEach(cells) { cell in
                    Button {
                        if let pick { return pick.run(channel) }
                        LivePlayback.play(channel, program: cell.program?.isAiring(at: Date()) == true ? cell.program : nil)
                    } label: {
                        GuideCellLabel(cell: cell, now: now)
                    }
                    .buttonStyle(GuideCellStyle(isAiring: cell.program?.isAiring(at: now) == true))
                    .frame(width: max(cell.end.timeIntervalSince(cell.start) * scale - Self.gap, 20),
                           height: LiveGuideView.rowHeight)
                    .focused(focus, equals: cell.id)
                    .contextMenu { LiveChannelMenu(channel: channel) }
                    .accessibilityLabel([channel.name, cell.program?.title].compactMap { $0 }.joined(separator: ", "))
                }
            }
        }
    }
}

private struct GuideCellLabel: View {
    let cell: GuideCell
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // The programme started before the window.
                if let p = cell.program, p.start < cell.start {
                    Image(systemName: "chevron.left").font(.caption2.weight(.bold))
                }
                Text(cell.program?.title ?? String(localized: "No Information"))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
            }
            if let p = cell.program {
                Text(GuideTime.range(p.start, p.stop))
                    .font(.caption2)
                    .opacity(0.7)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// A flat guide cell that turns white under focus, with the airing programme a shade lighter.
/// No focus lift: a wide cell scaled up spills into the channel column.
private struct GuideCellStyle: ButtonStyle {
    let isAiring: Bool

    func makeBody(configuration: Configuration) -> some View {
        CellBody(configuration: configuration, isAiring: isAiring)
    }

    private struct CellBody: View {
        let configuration: Configuration
        let isAiring: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .foregroundStyle(isFocused ? Color.black : Color.white)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isFocused ? Color.white : Color.white.opacity(isAiring ? 0.16 : 0.07))
                )
                .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 12, y: 6)
                .opacity(configuration.isPressed ? 0.8 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}

/// Half-hour marks over the guide's programme columns.
private struct TimeRuler: View {
    let windowStart: Date
    let scale: CGFloat
    let now: Date

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<Int(LiveGuideView.span / LiveGuideView.step), id: \.self) { i in
                let time = windowStart.addingTimeInterval(Double(i) * LiveGuideView.step)
                Text(time, format: .dateTime.hour().minute())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: LiveGuideView.step * scale, alignment: .leading)
            }
        }
    }
}

/// The focused programme: title, times, time left, episode and description, with its channel.
private struct GuideInfoPanel: View {
    let channel: LiveChannel?
    let program: EPGProgram?
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 48) {
            VStack(alignment: .leading, spacing: 10) {
                Text(program?.title ?? channel?.name ?? "")
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                if let program {
                    HStack(spacing: 16) {
                        if program.isAiring(at: now) {
                            Text("LIVE")
                                .font(.caption2.weight(.heavy))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Capsule().fill(.red))
                        }
                        Text(details(program))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if let description = program.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .frame(maxWidth: 1100, alignment: .leading)
                    }
                } else if let channel {
                    Text(channel.group ?? "").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let channel {
                VStack(alignment: .trailing, spacing: 8) {
                    ChannelLogo(channel: channel, size: CGSize(width: 220, height: 110), font: .largeTitle, namesChannel: false)
                    Text(channel.name).font(.caption.weight(.semibold)).lineLimit(1)
                    if let group = channel.group { Text(group).font(.caption2).foregroundStyle(.secondary) }
                }
                .frame(width: 320, alignment: .trailing)
            }
        }
    }

    private func details(_ p: EPGProgram) -> String {
        var parts = [GuideTime.range(p.start, p.stop)]
        if p.isAiring(at: now) {
            let left = Int(p.stop.timeIntervalSince(now) / 60)
            parts.append(String(localized: "\(left) min left"))
        } else if p.start > now {
            parts.append(p.start.formatted(.relative(presentation: .named)))
        }
        if let ep = p.episode, !ep.isEmpty { parts.append(ep) }
        if let cat = p.categories?.first { parts.append(cat) }
        return parts.joined(separator: " · ")
    }
}

enum GuideTime {
    static func range(_ start: Date, _ end: Date) -> String {
        let f = Date.FormatStyle.dateTime.hour().minute()
        return "\(start.formatted(f))–\(end.formatted(f))"
    }
}
