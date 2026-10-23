import Foundation

/// The local, Plex and Jellyfin libraries the profile may browse, for the Lists tab's
/// Libraries row. Kept between visits (the row draws at once) and dropped on a profile switch.
@MainActor
final class LibrariesStore: ObservableObject {
    static let shared = LibrariesStore()

    @Published private(set) var libraries: [LibraryInfo] = []
    private var profile: String?

    func refresh() async {
        let profile = APIClient.shared.profileID
        if self.profile != profile {
            libraries = []
            self.profile = profile
        }
        // A failure keeps what the row showed (a network blip shouldn't empty it).
        guard let fresh = try? await APIClient.shared.libraries(), APIClient.shared.profileID == profile else { return }
        libraries = fresh
    }
}

extension LibraryInfo {
    /// Under the tile's name: where it lives and what it holds, or that it is being scanned.
    var tileSubtitle: String {
        if isScanning { return String(localized: "Scanning…") }
        let kind = switch type {
        case "show": String(localized: "Shows")
        case "movie": String(localized: "Movies")
        default: String(localized: "Videos")
        }
        return "\(source.label) · \(kind)"
    }
}
