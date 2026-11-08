#if os(iOS)
import Foundation

/// Where downloads live: `Application Support/Downloads` (kept by the system under storage
/// pressure, unlike Caches, and excluded from iCloud / iTunes backup), the records in
/// `Application Support/downloads.json`, resume data and the saved posters next to the files.
/// Not actor-bound, so the URLSession delegate can move a finished file in place on its own queue.
enum DownloadStorage {
    static let directory: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var dir = support.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
    }()

    static var recordsURL: URL {
        directory.deletingLastPathComponent().appendingPathComponent("downloads.json")
    }

    static func fileURL(_ fileName: String) -> URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }

    static func resumeDataURL(_ id: String) -> URL {
        directory.appendingPathComponent("\(id).resume", isDirectory: false)
    }

    static func posterURL(_ id: String) -> URL {
        directory.appendingPathComponent("\(id).jpg", isDirectory: false)
    }

    static func fileExists(_ fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(fileName).path)
    }

    static func fileSize(_ fileName: String) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL(fileName).path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Moves a finished transfer into place (replacing a stale copy).
    static func moveIntoPlace(_ location: URL, fileName: String) throws {
        let destination = fileURL(fileName)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: location, to: destination)
    }

    /// Removes the file, its resume data and its poster.
    static func removeFiles(id: String, fileName: String) {
        for url in [fileURL(fileName), resumeDataURL(id), posterURL(id)] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func saveResumeData(_ data: Data?, id: String) {
        guard let data else { return }
        try? data.write(to: resumeDataURL(id), options: .atomic)
    }

    static func takeResumeData(_ id: String) -> Data? {
        let url = resumeDataURL(id)
        defer { try? FileManager.default.removeItem(at: url) }
        return try? Data(contentsOf: url)
    }

    static func hasResumeData(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: resumeDataURL(id).path)
    }

    /// Free space for files the user asked for ("important" usage, which counts space the
    /// system can purge for it), as the Settings app reports it.
    static var availableBytes: Int64? {
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                             .volumeTotalCapacityKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    static var totalBytes: Int64? {
        let values = try? directory.resourceValues(forKeys: [.volumeTotalCapacityKey])
        return values?.volumeTotalCapacity.map(Int64.init)
    }

    /// Bytes on disk in the downloads folder (finished files and posters).
    static func usedBytes() -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return files.reduce(0) { sum, url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return sum + Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
    }

    /// Saves the title's poster beside the file, so the list has art without the server.
    static func savePoster(_ raw: String?, id: String) async {
        guard let url = Artwork.url(raw, size: "w342") else { return }
        let request: URLRequest
        if url.scheme == ServerArtwork.scheme {
            guard let authorized = await ServerArtwork.request(for: url) else { return }
            request = authorized
        } else {
            request = URLRequest(url: url)
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode ?? 200 < 300, !data.isEmpty else { return }
        try? data.write(to: posterURL(id), options: .atomic)
    }
}
#endif
