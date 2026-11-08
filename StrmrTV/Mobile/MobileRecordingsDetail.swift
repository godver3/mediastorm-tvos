#if os(iOS)
import SwiftUI

/// A recording in the list: title, channel, when and how long, status and size.
struct MobileRecordingRow: View {
    let recording: Recording
    let busy: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: MobileRecordingStatus.symbol(recording.status))
                .font(.title2)
                .foregroundStyle(MobileRecordingStatus.color(recording.status))
                .frame(width: 32)
                .symbolEffect(.pulse, isActive: recording.status == .running)
            VStack(alignment: .leading, spacing: 3) {
                Text(recording.displayTitle).font(.headline).lineLimit(2)
                Text(recording.channelName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text(MobileRecordingStatus.when(recording)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let error = recording.visibleError {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                if busy {
                    ProgressView()
                } else {
                    Text(recording.status.label)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(MobileRecordingStatus.color(recording.status).opacity(0.18), in: Capsule())
                        .foregroundStyle(MobileRecordingStatus.color(recording.status))
                }
                if let size = recording.sizeText {
                    Text(size).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

enum MobileRecordingStatus {
    static func symbol(_ status: Recording.Status) -> String {
        switch status {
        case .pending: "clock"
        case .starting, .running: "record.circle.fill"
        case .completed: "play.circle.fill"
        case .cancelled: "stop.circle"
        case .failed, .unknown: "exclamationmark.circle"
        }
    }

    static func color(_ status: Recording.Status) -> Color {
        switch status {
        case .pending: .accentColor
        case .starting, .running: .red
        case .completed: .green
        case .cancelled: .secondary
        case .failed, .unknown: .orange
        }
    }

    /// "Sat 8 Nov, 21:00–22:00 · 1h".
    static func when(_ r: Recording) -> String {
        let day = r.startAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let times = "\(r.startAt.formatted(.dateTime.hour().minute()))–\(r.endAt.formatted(.dateTime.hour().minute()))"
        return [day + ", " + times, r.durationText].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// A recording's details and actions: Play (in progress while it records), Stop / Cancel and
/// Delete. Actions go back to the list through `perform`, which closes the sheet first.
struct MobileRecordingDetailSheet: View {
    let recording: Recording
    let perform: (RecordingAction) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(recording.status.label, systemImage: MobileRecordingStatus.symbol(recording.status))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MobileRecordingStatus.color(recording.status))
                        Text(recording.displayTitle).font(.title2.weight(.bold))
                        Text(recording.channelName).foregroundStyle(.secondary)
                        if let description = recording.description, !description.isEmpty {
                            Text(description).font(.callout).foregroundStyle(.secondary).padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    LabeledContent("Starts", value: recording.startAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Ends", value: recording.endAt.formatted(date: .abbreviated, time: .shortened))
                    if !recording.durationText.isEmpty { LabeledContent("Duration", value: recording.durationText) }
                    if let size = recording.sizeText { LabeledContent("Size", value: size) }
                    if recording.ruleId != nil { LabeledContent("Scheduled by", value: String(localized: "A recurring rule")) }
                    if let error = recording.visibleError {
                        Text(error).foregroundStyle(.red)
                    }
                }
                Section {
                    if recording.canPlay {
                        Button { perform(.play) } label: {
                            Label(recording.status == .running ? "Play In Progress" : "Play", systemImage: "play.fill")
                        }
                        .accessibilityIdentifier("recording.play")
                    }
                    if recording.canCancel {
                        Button(role: .destructive) { perform(.cancel) } label: {
                            Label(recording.status == .pending ? "Cancel Recording" : "Stop Recording", systemImage: "stop.circle")
                        }
                    }
                    if recording.canDelete {
                        Button(role: .destructive) { perform(.delete) } label: {
                            Label("Delete Recording", systemImage: "trash")
                        }
                    }
                } footer: {
                    if !recording.canDelete {
                        Text("This recording belongs to a recurring rule. Pause or delete the rule under Rules & Buffers.")
                    }
                }
            }
            .navigationTitle("Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
#endif
