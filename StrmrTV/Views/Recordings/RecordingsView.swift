import SwiftUI

/// What can hold focus on the Recordings screen.
enum RecordingsFocus: Hashable {
    case filter(RecordingFilter)
    case refresh
    case row(String)
    case action(RecordingAction)
}

/// A recording's actions, in the Expo TV screen's order.
enum RecordingAction: Hashable {
    case play, cancel, delete
}

/// Live TV recordings, a port of the Expo TV `TVRecordings` screen: filters (All, Upcoming,
/// Recording, Completed, History, each with its count) and Refresh across the top, the
/// recordings down the left, and the focused one's details and actions on the right: Play
/// (completed, or in progress while it records), Stop / Cancel and Delete, each confirmed.
/// Reached from the Recordings tab (Settings › Menu, hidden by default as in the Expo menu)
/// and from the Live tab's More menu (the Expo Live drawer's Recordings action).
struct RecordingsView: View {
    @StateObject private var store = RecordingsStore()
    @ObservedObject private var playback = PlaybackCoordinator.shared
    @FocusState private var focus: RecordingsFocus?
    @State private var selectedID: String?
    @State private var confirming: (action: RecordingAction, recording: Recording)?

    static let listWidth: CGFloat = 760

    private var selected: Recording? {
        store.visible.first { $0.id == selectedID } ?? store.visible.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            filters
            if let notice = store.notice ?? store.loadError.map({ (String(localized: "Unable to refresh recordings: \($0)"), true) }) {
                Text(notice.text)
                    .font(.callout)
                    .foregroundStyle(notice.isError ? .red : .secondary)
                    .lineLimit(2)
            }
            content
        }
        .padding(.horizontal, CardGridLayout.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .defaultFocus($focus, .filter(store.filter))
        .task { await store.load() }
        .task { await store.pollWhileActive() }
        // A recording played to its end (or stopped) may have changed status meanwhile.
        .onChange(of: playback.sessionsEnded) { Task { await store.load(refresh: true) } }
        .onChange(of: focus) { _, new in
            if case let .row(id)? = new { selectedID = id }
        }
        .onChange(of: store.filter) { selectedID = nil }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible, presenting: confirming) { pending in
            Button(confirmLabel(pending), role: .destructive) { Task { await run(pending) } }
            Button("Keep Recording", role: .cancel) {}
        }
        .task(id: store.notice?.text) {
            guard store.notice != nil else { return }
            try? await Task.sleep(for: .seconds(6))
            store.notice = nil
        }
    }

    /// Runs a confirmed action, then puts focus back where it can stay: the recording's first
    /// remaining action, or (once deleted) the row that took its place.
    private func run(_ pending: (action: RecordingAction, recording: Recording)) async {
        let index = store.visible.firstIndex { $0.id == pending.recording.id } ?? 0
        if pending.action == .delete { await store.delete(pending.recording) } else { await store.cancel(pending.recording) }
        if let updated = store.visible.first(where: { $0.id == pending.recording.id }) {
            focus = .action(RecordingDetailPanel.firstAction(for: updated))
        } else if !store.visible.isEmpty {
            let next = store.visible[min(index, store.visible.count - 1)]
            selectedID = next.id
            focus = .row(next.id)
        } else {
            focus = .filter(store.filter)
        }
    }

    // MARK: Header and filters

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LIVE TV LIBRARY").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("Recordings").font(.system(size: 50, weight: .medium))
            }
            Spacer()
            Text("\(store.recordings.count) saved & scheduled").foregroundStyle(.secondary)
        }
    }

    private var filters: some View {
        HStack(spacing: 20) {
            ForEach(RecordingFilter.allCases) { filter in
                Button {
                    store.filter = filter
                } label: {
                    HStack(spacing: 12) {
                        Text(filter.label)
                        Text("\(store.count(filter))").foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(RecordingFilterStyle(selected: store.filter == filter))
                .focused($focus, equals: .filter(filter))
                .accessibilityIdentifier("recordings-filter-\(filter.rawValue)")
            }
            Button {
                Task { await store.load(refresh: true) }
            } label: {
                Label(store.refreshing ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(store.refreshing)
            .focused($focus, equals: .refresh)
            .accessibilityIdentifier("recordings-refresh")
        }
        .font(.callout)
        .focusSection()
        // Up from the list lands on the chosen filter, not the one above the row.
        .defaultFocus($focus, .filter(store.filter), priority: .userInitiated)
    }

    // MARK: List and details

    @ViewBuilder private var content: some View {
        if store.loading {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 100)
        } else if let selected {
            HStack(alignment: .top, spacing: 60) {
                list(selected: selected)
                    .frame(width: Self.listWidth)
                    .focusSection()
                    // Left from the actions returns to the recording they belong to.
                    .defaultFocus($focus, .row(selected.id), priority: .userInitiated)
                RecordingDetailPanel(recording: selected, busy: store.busyID == selected.id, focus: $focus) { action in
                    if action == .play { RecordingPlayback.play(selected) } else { confirming = (action, selected) }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .focusSection()
            }
        } else {
            VStack(spacing: 14) {
                Text(store.recordings.isEmpty ? String(localized: "Your recordings will appear here") : store.filter.emptyText)
                    .font(.title3.weight(.bold))
                Text(store.recordings.isEmpty ? "Record a program from the Live TV guide to get started."
                     : "Choose another filter to browse your library.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 120)
        }
    }

    private func list(selected: Recording) -> some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(store.visible) { recording in
                    Button {
                        // Select moves to the actions, as on the Expo screen.
                        focus = .action(RecordingDetailPanel.firstAction(for: recording))
                    } label: {
                        RecordingRow(recording: recording, selected: recording.id == selected.id)
                    }
                    .buttonStyle(RecordingRowStyle())
                    .focused($focus, equals: .row(recording.id))
                    .accessibilityIdentifier("recording-row-\(recording.id)")
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 12)
        }
        .scrollClipDisabled()
    }

    // MARK: Confirmation (Expo's wording)

    private var confirmTitle: String {
        guard let confirming else { return "" }
        if confirming.action == .delete { return String(localized: "Delete this recording and its saved video? This cannot be undone.") }
        return confirming.recording.status == .running
            ? String(localized: "Stop this recording? Video captured so far will be kept.")
            : String(localized: "Cancel this scheduled recording? It will not start.")
    }

    private func confirmLabel(_ pending: (action: RecordingAction, recording: Recording)) -> String {
        if pending.action == .delete { return String(localized: "Delete Recording") }
        return pending.recording.status == .running ? String(localized: "Stop Recording") : String(localized: "Cancel Recording")
    }
}

/// A recording in the list: title (a red dot while it records), channel, status and start.
private struct RecordingRow: View {
    let recording: Recording
    let selected: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(recording.displayTitle).font(.headline).lineLimit(1)
                if recording.status == .running { Text("●").foregroundStyle(.red) }
            }
            Text(recording.channelName).font(.callout).lineLimit(1).opacity(0.75)
            Text("\(recording.status.label) · \(RecordingDetailPanel.dateText(recording.startAt))")
                .font(.caption).lineLimit(1).opacity(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
        .foregroundStyle(focused ? Color.black : Color.primary)
        .background(RoundedRectangle(cornerRadius: 14)
            .fill(focused ? Color.white : selected ? Color.white.opacity(0.14) : Color.white.opacity(0.05)))
    }
}

private struct RecordingRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RecordingRowBody(configuration: configuration)
    }

    private struct RecordingRowBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.98 : focused ? 1.03 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

/// A filter: the chosen one tinted, the focused one white (the Expo toolbar's tabs).
private struct RecordingFilterStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        FilterBody(configuration: configuration, selected: selected)
    }

    private struct FilterBody: View {
        let configuration: Configuration
        let selected: Bool
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .foregroundStyle(focused ? Color.black : Color.primary)
                .background(Capsule().fill(focused ? Color.white : selected ? Color.white.opacity(0.22) : Color.white.opacity(0.06)))
                .scaleEffect(configuration.isPressed ? 0.97 : focused ? 1.05 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
                .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}
