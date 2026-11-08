#if os(iOS)
import Foundation
import os

/// The background `URLSession` the downloads run in. Its transfers are carried out by the
/// system, so they keep going while the app is suspended and survive it being terminated
/// (not force-quit); on the next launch the session of the same identifier hands its tasks
/// back (`existingTasks`). Each task's `taskDescription` is its download's file name, whose
/// stem is the download's ID. Delegate events arrive on a private serial queue: a finished
/// file is moved into place there, before the callback returns (the system deletes it after),
/// then everything is forwarded to `DownloadManager` on the main actor.
final class DownloadSession: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let identifier = "com.strmr.app.nx.mobile.downloads"
    static let log = Logger(subsystem: "com.strmr.app", category: "downloads")

    /// What the session reports, keyed by download ID.
    enum Event {
        case progress(id: String, written: Int64, expected: Int64)
        case finished(id: String, bytes: Int64)
        case failed(id: String, message: String, resumeData: Data?)
        /// A task cancelled by `pause` / `delete` ended; nothing to record.
        case cancelled(id: String)
    }

    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "downloads.session"
        return queue
    }()

    private(set) lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        // Downloads are started by hand: run them now rather than at the system's leisure.
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.timeoutIntervalForResource = 7 * 24 * 3600
        return URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }()

    var onEvent: (@MainActor (Event) -> Void)?
    /// The system's completion handler from `handleEventsForBackgroundURLSession`, run once the
    /// session has delivered every pending event.
    private let handlerLock = NSLock()
    private var backgroundCompletion: (() -> Void)?
    /// Throttles progress to the UI: the last forward per task.
    private var lastProgress: [Int: Date] = [:]

    func setBackgroundCompletion(_ handler: @escaping () -> Void) {
        handlerLock.withLock { backgroundCompletion = handler }
        _ = session  // re-create the session so the system can deliver its events
    }

    func existingTasks() async -> [URLSessionDownloadTask] {
        await session.allTasks.compactMap { $0 as? URLSessionDownloadTask }
    }

    static func downloadID(_ task: URLSessionTask) -> String? {
        guard let name = task.taskDescription, !name.isEmpty else { return nil }
        return (name as NSString).deletingPathExtension
    }

    private func emit(_ event: Event) {
        guard let onEvent else { return }
        Task { @MainActor in onEvent(event) }
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = Self.downloadID(downloadTask) else { return }
        let now = Date()
        if let last = lastProgress[downloadTask.taskIdentifier], now.timeIntervalSince(last) < 0.5 { return }
        lastProgress[downloadTask.taskIdentifier] = now
        emit(.progress(id: id, written: totalBytesWritten,
                       expected: totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : 0))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64,
                    expectedTotalBytes: Int64) {
        guard let id = Self.downloadID(downloadTask) else { return }
        Self.log.notice("download \(id, privacy: .public) resumed at \(fileOffset) of \(expectedTotalBytes)")
        emit(.progress(id: id, written: fileOffset, expected: max(expectedTotalBytes, 0)))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = Self.downloadID(downloadTask), let fileName = downloadTask.taskDescription else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        guard (200..<300).contains(status) else {
            Self.log.error("download \(id, privacy: .public) answered HTTP \(status)")
            emit(.failed(id: id, message: String(localized: "The server answered \(status)."), resumeData: nil))
            return
        }
        do {
            try DownloadStorage.moveIntoPlace(location, fileName: fileName)
            let bytes = DownloadStorage.fileSize(fileName)
            Self.log.notice("download \(id, privacy: .public) finished: \(bytes) bytes")
            emit(.finished(id: id, bytes: bytes))
        } catch {
            Self.log.error("download \(id, privacy: .public) could not be saved: \(error.localizedDescription, privacy: .public)")
            emit(.failed(id: id, message: error.localizedDescription, resumeData: nil))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lastProgress[task.taskIdentifier] = nil
        guard let error, let id = Self.downloadID(task) else { return }
        let nsError = error as NSError
        let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            // Our own pause / delete; a pause saves its resume data itself.
            emit(.cancelled(id: id))
            return
        }
        Self.log.error("download \(id, privacy: .public) failed: \(error.localizedDescription, privacy: .public) (resumable \(resumeData != nil))")
        emit(.failed(id: id, message: error.localizedDescription, resumeData: resumeData))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let handler = handlerLock.withLock { () -> (() -> Void)? in
            defer { backgroundCompletion = nil }
            return backgroundCompletion
        }
        guard let handler else { return }
        // After the events above have reached the manager (they hop to the main actor too).
        Task { @MainActor in
            DownloadManager.shared.persistNow()
            handler()
        }
    }
}
#endif
