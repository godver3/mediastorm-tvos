#if os(iOS)
import Foundation

/// Settings › Downloads, kept on this device (as the Expo app keeps them in AsyncStorage):
/// Wi-Fi only, simultaneous downloads (1–3), delete once watched, keep the screen on, and the
/// Downloads list's sort.
@MainActor
final class DownloadSettings: ObservableObject {
    static let shared = DownloadSettings()

    enum Sort: String, CaseIterable, Identifiable {
        case newest, oldest, nameAscending, nameDescending
        var id: String { rawValue }

        var label: String {
            switch self {
            case .newest: String(localized: "Newest First")
            case .oldest: String(localized: "Oldest First")
            case .nameAscending: String(localized: "Name (A–Z)")
            case .nameDescending: String(localized: "Name (Z–A)")
            }
        }
    }

    private let defaults = UserDefaults.standard
    private enum Key {
        static let wifiOnly = "downloads.wifiOnly"
        static let maxConcurrent = "downloads.maxConcurrent"
        static let deleteWatched = "downloads.deleteWatched"
        static let keepScreenAwake = "downloads.keepScreenAwake"
        static let sort = "downloads.sort"
    }

    @Published var wifiOnly: Bool {
        didSet {
            defaults.set(wifiOnly, forKey: Key.wifiOnly)
            DownloadManager.shared.processQueue()
        }
    }

    @Published var maxConcurrent: Int {
        didSet {
            defaults.set(maxConcurrent, forKey: Key.maxConcurrent)
            DownloadManager.shared.processQueue()
        }
    }

    @Published var deleteWatched: Bool {
        didSet { defaults.set(deleteWatched, forKey: Key.deleteWatched) }
    }

    @Published var keepScreenAwake: Bool {
        didSet {
            defaults.set(keepScreenAwake, forKey: Key.keepScreenAwake)
            DownloadManager.shared.updateScreenAwake()
        }
    }

    @Published var sort: Sort {
        didSet { defaults.set(sort.rawValue, forKey: Key.sort) }
    }

    private init() {
        wifiOnly = defaults.bool(forKey: Key.wifiOnly)
        let stored = defaults.integer(forKey: Key.maxConcurrent)
        maxConcurrent = stored == 0 ? 1 : min(max(stored, 1), 3)
        deleteWatched = defaults.bool(forKey: Key.deleteWatched)
        keepScreenAwake = defaults.bool(forKey: Key.keepScreenAwake)
        sort = defaults.string(forKey: Key.sort).flatMap(Sort.init(rawValue:)) ?? .newest
    }
}
#endif
