import Foundation

private let log = AppLog(category: "LogUpload")

/// Sends the newest part of `strmr.log` to the server (`POST /api/logs/frontend`), as the Expo
/// app does: once a profile is in use, then every minute while the log has grown and no player
/// is up. The server keeps the latest upload per device; the admin UI's Logs page packages it
/// with the backend log for a bug report, so nobody needs a cable or `devicectl` to read it.
@MainActor
final class LogUploader: ObservableObject {
    static let shared = LogUploader()

    enum Status: Equatable {
        case idle, uploading, uploaded(Date), failed(String)
    }

    /// The last upload's outcome, shown in Settings › About.
    @Published private(set) var status: Status = .idle
    private var loop: Task<Void, Never>?
    private var uploadedThrough: UInt64?
    private var inFlight = false

    /// About 10,000 lines; well under the server's 10 MB limit and cheap over a slow route.
    private static let maxBytes = 1 << 20
    private static let interval: Duration = .seconds(60)

    private init() {}

    /// Starts the periodic upload; a running loop is kept (the first upload of a new profile
    /// session still goes out at once).
    func start() {
        if loop != nil { Task { await upload(reason: "profile") }; return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.upload(reason: "interval")
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    /// Uploads now, even when nothing new was logged; Settings' Upload Logs.
    @discardableResult
    func uploadNow() async -> Status {
        await upload(reason: "manual", force: true)
        return status
    }

    private func upload(reason: String, force: Bool = false) async {
        guard !inFlight, AppSession.shared.phase == .ready else { return }
        // Off during playback: the player owns the network, and its log lines go out after.
        guard force || !PlaybackCoordinator.shared.isPresentingPlayer else { return }
        let (text, written) = await LogFile.shared.tail(maxBytes: Self.maxBytes)
        guard force || written != uploadedThrough, !text.isEmpty else { return }

        inFlight = true
        status = .uploading
        defer { inFlight = false }
        do {
            try await APIClient.shared.uploadLogs(text, reason: reason)
            uploadedThrough = written
            status = .uploaded(Date())
        } catch {
            status = .failed(error.localizedDescription)
            log.error("upload (\(reason)) failed: \(error.localizedDescription)")
        }
    }
}
