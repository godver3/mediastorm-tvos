import Foundation

/// Recording from the guide (Expo's TV programme menu and channel action menu): record a
/// programme once or every airing on the channel, record a two-hour block, and stop or cancel
/// what is already set. The guide marks scheduled / recording programmes from `recordings`,
/// refreshed every 10 s while Live is on screen and straight after each action.
extension LiveStore {
    /// Refreshes `recordings` until the calling view's task ends.
    func pollRecordings() async {
        while !Task.isCancelled {
            await refreshRecordings()
            try? await Task.sleep(for: .seconds(10))
        }
    }

    /// Keeps what was last known through a transient failure.
    func refreshRecordings() async {
        guard let fresh = try? await APIClient.shared.activeRecordings(), fresh != recordings else { return }
        recordings = fresh
    }

    /// The active recording overlapping `program` on the channel, else (without a programme) the
    /// one recording the channel now; a running one wins (Expo `findLiveRecording`).
    func recording(on channel: LiveChannel, during program: EPGProgram? = nil, now: Date = Date()) -> Recording? {
        let matches = recordings.filter { r in
            guard r.channelId == channel.id, r.canCancel else { return false }
            if let program, program.stop > program.start { return r.startAt < program.stop && r.endAt > program.start }
            return r.startAt <= now && r.endAt > now
        }
        return matches.first { $0.status == .running } ?? matches.first
    }

    func record(_ program: EPGProgram, on channel: LiveChannel) {
        perform(success: String(localized: "Recording scheduled for \(program.title).")) {
            try await APIClient.shared.recordProgram(program, on: channel)
        }
    }

    /// `newOnly` skips airings the guide flags as reruns; re-recording a series with the other
    /// choice switches the existing rule.
    func recordSeries(_ program: EPGProgram, on channel: LiveChannel, newOnly: Bool = false) {
        let success = newOnly
            ? String(localized: "Recording new episodes of “\(program.title)” on \(channel.name).")
            : String(localized: "Series recording set for “\(program.title)” on \(channel.name).")
        perform(success: success) {
            try await APIClient.shared.recordSeries(program.title, on: channel, newOnly: newOnly)
        }
    }

    func recordTwoHours(_ channel: LiveChannel) {
        perform(success: String(localized: "2 hour recording scheduled for \(channel.name).")) {
            try await APIClient.shared.recordTimeBlock(channel, duration: 2 * 3600)
        }
    }

    /// Stops a recording in progress (what was captured is kept) or cancels a scheduled one.
    func cancel(_ recording: Recording) {
        let stopping = recording.status == .running || recording.status == .starting
        perform(success: stopping ? String(localized: "Recording stopped.") : String(localized: "Scheduled recording cancelled.")) {
            try await APIClient.shared.cancelRecording(recording.id)
        }
    }

    private func perform(success: String, _ action: @escaping () async throws -> Void) {
        guard recordingTask == nil else { return }
        recordingTask = Task {
            defer { recordingTask = nil }
            do {
                try await action()
                show(notice: success)
                await refreshRecordings()
            } catch {
                if !(error is CancellationError) { show(notice: error.localizedDescription) }
            }
        }
    }
}
