#if os(iOS)
import Foundation

/// The queue: pending downloads start, oldest first, while fewer than `maxConcurrent` run;
/// with Wi-Fi Only on and no Wi-Fi they wait (running ones are suspended with their resume
/// data, as the Expo app holds them). Re-attaches to the session's tasks after a relaunch and
/// records what the session reports.
extension DownloadManager {
    func processQueue() {
        guard reattached else { return }
        let holdForWifi = settings.wifiOnly && !onUnmeteredNetwork
        if holdForWifi {
            for item in items where item.status == .downloading {
                suspendTask(item.id)
                update(item.id) {
                    $0.status = .pending
                    $0.bytesPerSecond = 0
                }
            }
        }
        for item in items where item.status == .pending {
            let reason: DownloadItem.WaitingReason? = holdForWifi ? .wifi : nil
            if item.waitingReason != reason { update(item.id) { $0.waitingReason = reason } }
        }
        if !holdForWifi {
            var running = items.filter { $0.status == .downloading }.count
            let queued = items.filter { $0.status == .pending && !cancelling.contains($0.id) }
                .sorted { $0.createdAt < $1.createdAt }
            for item in queued where running < settings.maxConcurrent {
                startTask(item)
                running += 1
            }
        }
        updateScreenAwake()
        persistSoon()
    }

    /// Starts (or, from its resume data, continues) one download in the background session.
    private func startTask(_ item: DownloadItem) {
        let task: URLSessionDownloadTask
        if let data = DownloadStorage.takeResumeData(item.id) {
            task = session.session.downloadTask(withResumeData: data)
            DownloadSession.log.notice("resuming \(item.displayTitle, privacy: .public) from \(item.bytesWritten) bytes")
        } else {
            var request = URLRequest(url: APIClient.shared.streamURL(for: item.streamPath))
            for (name, value) in APIClient.shared.mediaHeaders { request.setValue(value, forHTTPHeaderField: name) }
            // The system enforces Wi-Fi Only even while the app is suspended.
            request.allowsCellularAccess = !settings.wifiOnly
            request.allowsExpensiveNetworkAccess = !settings.wifiOnly
            task = session.session.downloadTask(with: request)
            update(item.id) { $0.bytesWritten = 0 }
            DownloadSession.log.notice("starting \(item.displayTitle, privacy: .public)")
        }
        task.taskDescription = item.fileName
        if item.expectedBytes > 0 { task.countOfBytesClientExpectsToReceive = item.expectedBytes }
        tasks[item.id] = task
        update(item.id) {
            $0.status = .downloading
            $0.waitingReason = nil
            $0.errorMessage = nil
        }
        speedSamples[item.id] = nil
        task.resume()
    }

    /// After a relaunch: adopt the session's surviving tasks, cancel ones no record owns, and
    /// requeue downloads that were running when the app went away but have no task (resuming
    /// from saved resume data when there is some, else from the start).
    func reattach() async {
        let existing = await session.existingTasks()
        var adopted: Set<String> = []
        for task in existing {
            guard let id = DownloadSession.downloadID(task), let item = item(id), item.isActive else {
                task.cancel()
                continue
            }
            // Finished (or failed) while the app was away: the session is about to deliver
            // the outcome, so the download is neither requeued nor restarted.
            if task.state == .completed || task.state == .canceling {
                adopted.insert(id)
                continue
            }
            tasks[id] = task
            adopted.insert(id)
            if task.state == .suspended { task.resume() }
            update(id) {
                $0.status = .downloading
                $0.bytesWritten = max($0.bytesWritten, task.countOfBytesReceived)
                if task.countOfBytesExpectedToReceive > 0 { $0.expectedBytes = task.countOfBytesExpectedToReceive }
            }
        }
        for item in items where item.status == .downloading && !adopted.contains(item.id) {
            update(item.id) {
                $0.status = .pending
                $0.bytesPerSecond = 0
            }
        }
        DownloadSession.log.notice("re-attached \(adopted.count) of \(existing.count) session task(s); \(self.items.count) download(s)")
        reattached = true
        processQueue()
    }

    // MARK: Session events

    func handle(_ event: DownloadSession.Event) {
        switch event {
        case let .progress(id, written, expected):
            guard tasks[id] != nil else { return }
            let now = Date()
            let last = speedSamples[id]
            speedSamples[id] = (written, now)
            update(id) { item in
                if expected > 0 { item.expectedBytes = expected }
                if let last, now.timeIntervalSince(last.at) > 0.1, written >= last.bytes {
                    let instant = Double(written - last.bytes) / now.timeIntervalSince(last.at)
                    item.bytesPerSecond = item.bytesPerSecond > 0 ? item.bytesPerSecond * 0.3 + instant * 0.7 : instant
                }
                item.bytesWritten = written
            }
            persistSoon()
        case let .finished(id, bytes, taskID):
            // A second transfer of the same download (requeued before this one's outcome
            // arrived) has nothing left to do.
            if let current = tasks.removeValue(forKey: id), current.taskIdentifier != taskID {
                cancelling.insert(id)
                current.cancel()
            }
            speedSamples[id] = nil
            update(id) {
                $0.status = .completed
                $0.bytesWritten = bytes
                $0.expectedBytes = bytes
                $0.bytesPerSecond = 0
                $0.completedAt = Date()
                $0.waitingReason = nil
            }
            persistNow()
            refreshUsage()
            processQueue()
        case let .failed(id, message, resumeData):
            tasks[id] = nil
            speedSamples[id] = nil
            guard item(id) != nil else { return }
            DownloadStorage.saveResumeData(resumeData, id: id)
            update(id) {
                $0.status = .failed
                $0.errorMessage = message
                $0.bytesPerSecond = 0
            }
            persistNow()
            processQueue()
        case let .cancelled(id):
            speedSamples[id] = nil
            // Give a pause's resume data a moment to land before the queue reuses the slot.
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                cancelling.remove(id)
                processQueue()
            }
        }
    }
}
#endif
