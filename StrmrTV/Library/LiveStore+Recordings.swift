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
        async let active = try? APIClient.shared.activeRecordings()
        async let rules = try? APIClient.shared.recordingRules()
        if let fresh = await active, fresh != recordings { recordings = fresh }
        if let fresh = await rules, fresh != recordingRules { recordingRules = fresh }
    }

    /// The rule that records `program` on the channel, if any: a title rule for it here or on
    /// every channel first, then a regex rule.
    func seriesRule(for program: EPGProgram, on channel: LiveChannel) -> RecordingRule? {
        let matches = recordingRules.filter { $0.covers(title: program.title, on: channel) }
        return matches.first { !$0.isRegex } ?? matches.first
    }

    /// Deletes the rule; the server cancels the airings it had scheduled (one already
    /// recording keeps going, and can be stopped on its own).
    func cancelSeries(_ rule: RecordingRule) {
        perform(success: String(localized: "Series recording cancelled for \(rule.summary).")) {
            try await APIClient.shared.deleteRecordingRule(rule.id)
        }
    }

    /// Switches an existing rule between every airing and new episodes only.
    func setSeries(_ rule: RecordingRule, newOnly: Bool) {
        let success = newOnly
            ? String(localized: "Now recording only new episodes of \(rule.summary).")
            : String(localized: "Now recording every airing of \(rule.summary).")
        perform(success: success) {
            try await APIClient.shared.updateRecordingRule(rule.id, newOnly: newOnly)
        }
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
