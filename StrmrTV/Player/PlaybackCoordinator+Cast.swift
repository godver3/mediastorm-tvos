import Foundation

extension PlaybackCoordinator {
    /// On iOS, a cast armed on the details page takes the resolved stream instead of the player
    /// (`CastController.claim`). Never on tvOS.
    func castClaims(_ request: PlaybackRequest, path: String, tracks: TrackPreferences) -> Bool {
        #if os(iOS)
        CastController.shared.claim(request, path: path, tracks: tracks)
        #else
        false
        #endif
    }
}
