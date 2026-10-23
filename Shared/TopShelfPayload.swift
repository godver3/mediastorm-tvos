import Foundation

/// What the app hands the Top Shelf extension through the App Group container: the rows
/// to show on the Apple TV home screen when Strmr sits in the top row. Compiled into both
/// the app and the extension.
struct TopShelfPayload: Codable, Equatable, Sendable {
    struct Section: Codable, Equatable, Sendable {
        let id: String
        let title: String
        let items: [Item]
    }

    struct Item: Codable, Equatable, Sendable {
        let id: String
        let title: String
        /// poster | hdtv | square
        let imageShape: String
        /// Public artwork (TMDB); the system fetches it without the app's credentials.
        let imageURL: String?
        /// Select: opens the details page.
        let displayURL: String
        /// Play/Pause: opens the details page and starts its primary action (Resume / Play).
        let playURL: String?
        /// 0–1, drawn as a progress bar under the art.
        let playbackProgress: Double?
    }

    let sections: [Section]
}

enum TopShelfStore {
    /// Shared with the extension; both targets carry it in their entitlements.
    static let appGroup = "group.com.strmr.app.nx"
    static let payloadKey = "topShelfPayload"
    /// The extension's last load, for diagnosing an empty shelf.
    static let statusKey = "topShelfExtensionStatus"

    /// The App Group's shared defaults. Not a file in the group container: on a device,
    /// tvOS refuses writes there outside `Library/Caches` (the simulator allows them), and
    /// caches can be purged. The Expo app's Top Shelf uses shared defaults too.
    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func read() -> TopShelfPayload? {
        guard let data = defaults?.data(forKey: payloadKey), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(TopShelfPayload.self, from: data)
    }
}
