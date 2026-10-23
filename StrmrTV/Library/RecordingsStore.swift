import Foundation

/// The Recordings screen's state: the profile's recordings, the filter, and the cancel /
/// delete actions (Expo's `NewRecordingsScreen` handlers). While anything is scheduled or
/// recording the list refreshes itself every 30 s, so a status change shows up on its own.
@MainActor
final class RecordingsStore: ObservableObject {
    @Published private(set) var recordings: [Recording] = []
    @Published private(set) var loading = false
    @Published private(set) var refreshing = false
    @Published private(set) var loadError: String?
    @Published var filter: RecordingFilter = .all
    /// The recording an action is running on.
    @Published private(set) var busyID: String?
    /// The last action's outcome ("Deleted …", or the server's error), shown under the header.
    @Published var notice: (text: String, isError: Bool)?

    private let api = APIClient.shared
    private let log = AppLog(category: "recordings")

    var visible: [Recording] { recordings.filter(filter.matches) }

    func count(_ filter: RecordingFilter) -> Int { recordings.filter(filter.matches).count }

    func recording(_ id: String?) -> Recording? { recordings.first { $0.id == id } }

    /// First load shows a spinner; later ones (Refresh, after an action) keep the list up.
    func load(refresh: Bool = false) async {
        if refresh { refreshing = true } else if recordings.isEmpty { loading = true }
        defer { loading = false; refreshing = false }
        do {
            recordings = try await api.recordings()
            loadError = nil
            log.info("loaded \(self.recordings.count) recordings")
        } catch is CancellationError {
        } catch {
            loadError = error.localizedDescription
            log.error("load failed: \(error.localizedDescription)")
        }
    }

    /// Refreshes every 30 s while a recording is scheduled or running; ends with the view's task.
    func pollWhileActive() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            if recordings.contains(where: \.canCancel) { await load(refresh: true) }
        }
    }

    func cancel(_ recording: Recording) async {
        await perform(recording, verb: "cancel") {
            try await self.api.cancelRecording(recording.id)
            return String(localized: "Cancelled \(recording.displayTitle).")
        }
    }

    func delete(_ recording: Recording) async {
        await perform(recording, verb: "delete") {
            try await self.api.deleteRecording(recording.id)
            return String(localized: "Deleted \(recording.displayTitle).")
        }
    }

    private func perform(_ recording: Recording, verb: String, _ action: () async throws -> String) async {
        guard busyID == nil else { return }
        busyID = recording.id
        defer { busyID = nil }
        do {
            let text = try await action()
            log.notice("\(verb) \(recording.id)")
            notice = (text, false)
            await load(refresh: true)
        } catch {
            log.error("\(verb) \(recording.id) failed: \(error.localizedDescription)")
            notice = (error.localizedDescription, true)
        }
    }
}
