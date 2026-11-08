#if os(iOS)
import Foundation
import Network
import UIKit

/// Offline downloads, as the Expo app's `downloadManager`: the records (persisted as JSON),
/// a queue that runs up to `settings.maxConcurrent` transfers in the background session,
/// pause / resume through URLSession resume data, delete, the disk-space check before a
/// download starts, and the Wi-Fi-only hold. The transfers themselves live in
/// `DownloadSession`; `+Queue` starts and re-attaches them.
@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var items: [DownloadItem] = []
    /// On Wi-Fi (or Ethernet): a connection that is not marked expensive.
    @Published private(set) var onUnmeteredNetwork = true
    @Published private(set) var usedBytes: Int64 = 0

    let settings = DownloadSettings.shared
    let session = DownloadSession()
    /// Running transfers, by download ID.
    var tasks: [String: URLSessionDownloadTask] = [:]
    /// Downloads being paused / deleted, whose cancellation the session will report.
    var cancelling: Set<String> = []
    var speedSamples: [String: (bytes: Int64, at: Date)] = [:]
    var reattached = false
    private let pathMonitor = NWPathMonitor()
    private var persistScheduled = false
    private var heldScreenAwake = false

    enum DownloadError: LocalizedError {
        case notEnoughSpace(needed: Int64, free: Int64)
        case alreadyDownloaded

        var errorDescription: String? {
            switch self {
            case let .notEnoughSpace(needed, free):
                String(localized: "Not enough storage for this download: it needs \(DownloadFormat.bytes(needed)) and \(DownloadFormat.bytes(free)) is free.")
            case .alreadyDownloaded:
                String(localized: "This is already downloaded.")
            }
        }
    }

    private init() {
        items = Self.loadRecords()
        refreshUsage()
        session.onEvent = { [weak self] event in self?.handle(event) }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let unmetered = path.status == .satisfied && !path.isExpensive
            Task { @MainActor in self?.networkChanged(unmetered: unmetered) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "downloads.path"))
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateScreenAwake()
                self?.processQueue()
            }
        }
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.persistNow()
                self?.updateScreenAwake()
            }
        }
        Task { await reattach() }
    }

    // MARK: Lookup

    func item(_ id: String) -> DownloadItem? { items.first { $0.id == id } }

    /// The movie's or episode's download, if there is one.
    func download(titleID: String, season: Int?, episode: Int?) -> DownloadItem? {
        items.first { $0.matches(titleID: titleID, season: season, episode: episode) }
    }

    func download(for target: DetailsTarget, episode: Episode?) -> DownloadItem? {
        download(titleID: target.titleID, season: target.isMovie ? nil : episode?.seasonNumber,
                 episode: target.isMovie ? nil : episode?.episodeNumber)
    }

    var completed: [DownloadItem] { items.filter { $0.status == .completed } }
    var activeCount: Int { items.filter(\.isActive).count }

    /// The local file of a finished download.
    func fileURL(_ item: DownloadItem) -> URL { DownloadStorage.fileURL(item.fileName) }

    func posterFileURL(_ item: DownloadItem) -> URL? {
        let url = DownloadStorage.posterURL(item.id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: Start

    /// Queues a download of the movie (or episode) at `streamPath`. An existing download of
    /// it is kept when it finished or is running, resumed when paused, and replaced when it
    /// failed. Throws when the volume doesn't have room for `expectedBytes` plus a 10% margin.
    @discardableResult
    func start(target: DetailsTarget, episode: Episode?, streamPath: String, releaseName: String?,
               expectedBytes: Int64) throws -> DownloadItem {
        if let existing = download(for: target, episode: episode) {
            switch existing.status {
            case .completed, .downloading, .pending:
                return existing
            case .paused:
                resume(existing.id)
                return existing
            case .failed:
                delete(existing.id)
            }
        }
        if expectedBytes > 0, let free = DownloadStorage.availableBytes,
           Double(free) < Double(expectedBytes) * 1.1 {
            throw DownloadError.notEnoughSpace(needed: expectedBytes, free: free)
        }
        let item = DownloadItem(target: target, episode: episode, streamPath: streamPath,
                                releaseName: releaseName, expectedBytes: expectedBytes)
        items.append(item)
        DownloadSession.log.notice("queued \(item.displayTitle, privacy: .public) (\(expectedBytes) bytes)")
        persistNow()
        let poster = target.posterURL
        Task.detached { await DownloadStorage.savePoster(poster, id: item.id) }
        processQueue()
        return item
    }

    // MARK: Pause, resume, delete

    func pause(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].isActive else { return }
        items[index].status = .paused
        items[index].waitingReason = nil
        items[index].bytesPerSecond = 0
        suspendTask(id)
        persistNow()
        processQueue()
    }

    /// Resume a paused download, or retry a failed one (from its resume data when it left any).
    func resume(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              items[index].status == .paused || items[index].status == .failed else { return }
        items[index].status = .pending
        items[index].errorMessage = nil
        persistNow()
        processQueue()
    }

    func delete(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        if let task = tasks.removeValue(forKey: id) {
            cancelling.insert(id)
            task.cancel()
        }
        DownloadStorage.removeFiles(id: item.id, fileName: item.fileName)
        DownloadSession.log.notice("deleted \(item.displayTitle, privacy: .public)")
        persistNow()
        refreshUsage()
        processQueue()
    }

    func delete(_ ids: some Sequence<String>) {
        for id in Array(ids) { delete(id) }
    }

    /// Cancels the running transfer, keeping its resume data for later.
    func suspendTask(_ id: String) {
        guard let task = tasks.removeValue(forKey: id) else { return }
        cancelling.insert(id)
        task.cancel { data in
            Task { @MainActor in
                // Not when the download was deleted meanwhile.
                if DownloadManager.shared.item(id) != nil { DownloadStorage.saveResumeData(data, id: id) }
            }
        }
    }

    // MARK: Updates

    func update(_ id: String, _ change: (inout DownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }

    private func networkChanged(unmetered: Bool) {
        guard unmetered != onUnmeteredNetwork else { return }
        onUnmeteredNetwork = unmetered
        DownloadSession.log.notice("network is \(unmetered ? "unmetered" : "metered / offline", privacy: .public)")
        processQueue()
    }

    func refreshUsage() {
        Task.detached(priority: .utility) {
            let used = DownloadStorage.usedBytes()
            await MainActor.run { DownloadManager.shared.usedBytes = used }
        }
    }

    /// Keep the screen on while a download runs in the foreground (Settings › Downloads).
    func updateScreenAwake() {
        let want = settings.keepScreenAwake && UIApplication.shared.applicationState == .active
            && items.contains { $0.status == .downloading }
        guard want != heldScreenAwake else { return }
        heldScreenAwake = want
        UIApplication.shared.isIdleTimerDisabled = want
    }

    // MARK: Persistence

    private static func loadRecords() -> [DownloadItem] {
        guard let data = try? Data(contentsOf: DownloadStorage.recordsURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var records = try? decoder.decode([DownloadItem].self, from: data) else { return [] }
        // A finished download whose file is gone (deleted by hand, restored backup) is dropped.
        records.removeAll { $0.status == .completed && !DownloadStorage.fileExists($0.fileName) }
        return records
    }

    /// Writes the records soon, once per burst of progress updates.
    func persistSoon() {
        guard !persistScheduled else { return }
        persistScheduled = true
        Task {
            try? await Task.sleep(for: .seconds(5))
            persistNow()
        }
    }

    func persistNow() {
        persistScheduled = false
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: DownloadStorage.recordsURL, options: .atomic)
    }
}
#endif
