#if os(iOS)
import SwiftUI

/// The phone's Recordings screen (Expo's `NewRecordingsScreen`): the profile's Live TV
/// recordings in sections (Recording now, Upcoming, Completed, History), or one of them picked
/// from the filter menu. Tap plays a recording that has a file (a growing one plays in
/// progress) and opens the details of one that doesn't; swipe or long-press to stop / cancel
/// or delete, each confirmed. Rules & Buffers holds the recurring recordings and the default
/// padding. Pull to refresh; while anything is scheduled or recording the list refreshes itself.
struct MobileRecordingsView: View {
    @StateObject private var store = RecordingsStore()
    @ObservedObject private var playback = PlaybackCoordinator.shared
    @State private var details: Recording?
    @State private var confirming: MobileRecordingConfirm?
    /// The details sheet's choice, run once the sheet is gone (a player or dialog can't come up
    /// while it is still dismissing).
    @State private var pending: (action: RecordingAction, recording: Recording)?

    var body: some View {
        content
            .navigationTitle("Recordings")
            .toolbar { toolbar }
            .refreshable { await store.load(refresh: true) }
            .sheet(item: $details, onDismiss: runPending) { recording in
                MobileRecordingDetailSheet(recording: store.recording(recording.id) ?? recording) { action in
                    pending = (action, recording)
                    details = nil
                }
            }
            .confirmationDialog(confirming?.title ?? "", isPresented: Binding(
                get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                                titleVisibility: .visible, presenting: confirming) { pending in
                Button(pending.confirmLabel, role: .destructive) {
                    Task {
                        if pending.action == .delete { await store.delete(pending.recording) } else { await store.cancel(pending.recording) }
                    }
                }
                Button("Keep Recording", role: .cancel) {}
            } message: { pending in
                Text(pending.message)
            }
            .safeAreaInset(edge: .bottom) { noticeBar }
            .task { await store.load() }
            .task { await store.pollWhileActive() }
            // A recording played to its end (or stopped) may have changed status meanwhile.
            .onChange(of: playback.sessionsEnded) { Task { await store.load(refresh: true) } }
            .task(id: store.notice?.text) {
                guard store.notice != nil else { return }
                try? await Task.sleep(for: .seconds(5))
                store.notice = nil
            }
    }

    @ViewBuilder private var content: some View {
        if store.loading, store.recordings.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = store.loadError, store.recordings.isEmpty {
            ContentUnavailableView {
                Label("Couldn't Load Recordings", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { Task { await store.load() } }
            }
        } else if store.visible.isEmpty {
            ContentUnavailableView {
                Label(store.filter.emptyText, systemImage: "record.circle")
            } description: {
                Text("Long-press a channel or a guide programme on Live TV to record it.")
            }
        } else {
            List {
                ForEach(sections, id: \.filter) { section in
                    Section {
                        ForEach(section.recordings) { row($0) }
                    } header: {
                        if store.filter == .all { Text(section.filter.label) }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    /// Under All, one section per status in the order that matters; otherwise the one filter.
    private var sections: [(filter: RecordingFilter, recordings: [Recording])] {
        guard store.filter == .all else { return [(store.filter, store.visible)] }
        return [RecordingFilter.recording, .upcoming, .completed, .history].compactMap { filter in
            var items = store.recordings.filter(filter.matches)
            // Upcoming soonest first; the rest newest first.
            items.sort { filter == .upcoming ? $0.startAt < $1.startAt : $0.startAt > $1.startAt }
            return items.isEmpty ? nil : (filter, items)
        }
    }

    private func row(_ recording: Recording) -> some View {
        Button {
            if recording.canPlay { RecordingPlayback.play(recording) } else { details = recording }
        } label: {
            MobileRecordingRow(recording: recording, busy: store.busyID == recording.id)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recording-\(recording.id)")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if recording.canDelete {
                Button(role: .destructive) { confirming = .init(action: .delete, recording: recording) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            if recording.canCancel {
                Button { confirming = .init(action: .cancel, recording: recording) } label: {
                    Label(recording.status == .pending ? "Cancel" : "Stop", systemImage: "stop.circle")
                }
                .tint(.orange)
            }
        }
        .contextMenu {
            if recording.canPlay {
                Button { RecordingPlayback.play(recording) } label: {
                    Label(recording.status == .running ? "Play In Progress" : "Play", systemImage: "play.fill")
                }
            }
            Button { details = recording } label: { Label("Details", systemImage: "info.circle") }
            if recording.canCancel {
                Button(role: .destructive) { confirming = .init(action: .cancel, recording: recording) } label: {
                    Label(recording.status == .pending ? "Cancel Recording" : "Stop Recording", systemImage: "stop.circle")
                }
            }
            if recording.canDelete {
                Button(role: .destructive) { confirming = .init(action: .delete, recording: recording) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func runPending() {
        guard let (action, recording) = pending else { return }
        pending = nil
        switch action {
        case .play: RecordingPlayback.play(recording)
        case .cancel, .delete: confirming = .init(action: action, recording: recording)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            NavigationLink {
                MobileRecordingRulesView()
            } label: {
                Label("Rules & Buffers", systemImage: "repeat.circle")
            }
            .accessibilityIdentifier("recordings.rules")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Show", selection: $store.filter) {
                    ForEach(RecordingFilter.allCases) { filter in
                        Text("\(filter.label) (\(store.count(filter)))").tag(filter)
                    }
                }
            } label: {
                Label("Filter", systemImage: store.filter == .all
                      ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }
            .accessibilityIdentifier("recordings.filter")
        }
    }

    @ViewBuilder private var noticeBar: some View {
        if let notice = store.notice {
            Text(notice.text)
                .font(.footnote)
                .foregroundStyle(notice.isError ? .red : .primary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 8)
        }
    }
}

/// A cancel / stop or delete waiting for confirmation.
struct MobileRecordingConfirm: Identifiable {
    let action: RecordingAction
    let recording: Recording

    var id: String { "\(action)|\(recording.id)" }

    private var stopping: Bool { recording.status == .running || recording.status == .starting }

    var title: String {
        switch action {
        case .delete: String(localized: "Delete “\(recording.displayTitle)”?")
        default: stopping ? String(localized: "Stop recording “\(recording.displayTitle)”?")
            : String(localized: "Cancel “\(recording.displayTitle)”?")
        }
    }

    var message: String {
        switch action {
        case .delete: String(localized: "The recording and its file are removed from the server.")
        default: stopping ? String(localized: "What has been recorded so far is kept.")
            : String(localized: "It won't be recorded.")
        }
    }

    var confirmLabel: String {
        switch action {
        case .delete: String(localized: "Delete Recording")
        default: stopping ? String(localized: "Stop Recording") : String(localized: "Cancel Recording")
        }
    }
}
#endif
