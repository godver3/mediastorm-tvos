import SwiftUI

/// The focused recording on the Recordings screen (the Expo TV screen's details column):
/// status, title, channel, times, duration and size, description, error, and the actions
/// it allows.
struct RecordingDetailPanel: View {
    let recording: Recording
    let busy: Bool
    var focus: FocusState<RecordingsFocus?>.Binding
    let perform: (RecordingAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text((recording.status == .running ? "● " : "") + recording.status.label.uppercased())
                .font(.callout.weight(.bold))
                .foregroundStyle(statusColor)
            Text(recording.displayTitle).font(.title2.weight(.bold)).lineLimit(2)
            Text(recording.channelName).font(.headline).foregroundStyle(.secondary).lineLimit(1)
            Text("\(Self.dateText(recording.startAt)) — \(Self.dateText(recording.endAt))").foregroundStyle(.secondary)
            Text(facts).foregroundStyle(.secondary)
            Text(recording.description.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "No program description available."))
                .font(.callout)
                .lineLimit(5)
                .padding(.top, 6)
            if let error = recording.visibleError {
                Text(error).font(.callout).foregroundStyle(.red).lineLimit(3)
            }
            actions.padding(.top, 20)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 18) {
            if recording.canPlay {
                button(.play, recording.status == .running ? "Play in Progress" : "Play Recording", "play.fill")
            }
            if recording.canCancel {
                button(.cancel, recording.status == .running ? "Stop Recording" : "Cancel Scheduled Recording",
                       "stop.circle")
            }
            if recording.canDelete {
                button(.delete, "Delete Recording", "trash")
            }
        }
        .disabled(busy)
    }

    private func button(_ action: RecordingAction, _ title: LocalizedStringKey, _ symbol: String) -> some View {
        Button { perform(action) } label: {
            Label(title, systemImage: symbol).frame(minWidth: 480, alignment: .leading)
        }
        .focused(focus, equals: .action(action))
        .accessibilityIdentifier("recording-\(action)")
    }

    /// Duration, and the file's size once something is recorded.
    private var facts: String {
        [recording.durationText, recording.sizeText].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
    }

    private var statusColor: Color {
        switch recording.status {
        case .completed: .green
        case .failed, .unknown, .running: .red
        case .cancelled: .secondary
        case .pending, .starting: .orange
        }
    }

    /// The action Select on a list row moves to: the first one shown.
    static func firstAction(for recording: Recording) -> RecordingAction {
        recording.canPlay ? .play : recording.canCancel ? .cancel : .delete
    }

    /// "Oct 22, 7:00 PM" (Expo's `formatDateTime`).
    static func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
