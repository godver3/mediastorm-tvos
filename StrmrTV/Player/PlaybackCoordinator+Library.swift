import Foundation

extension PlaybackCoordinator {
    /// Plays a library copy (local, Plex or Jellyfin) instead of searching: the server names the
    /// file's stream path and streams it like any other source. There is no server track pick,
    /// so the profile's languages choose the audio and subtitles once the engine has read them.
    /// `known` is the file's playback info when the caller already fetched it.
    func playLibrary(_ request: PlaybackRequest, version: LibraryVersion, playback known: LibraryPlaybackInfo? = nil) {
        var request = request
        request.libraryVersion = version
        begin(request, stage: String(localized: "Preparing…")) {
            let playback = if let known { known } else { try await APIClient.shared.libraryPlayback(itemID: version.item.id) }
            await TrackSettingsStore.shared.loadProfileValues()
            return (playback.streamPath, TrackPreferences.library,
                    SourceSwitch.Current(releaseName: version.releaseName, streamPath: playback.streamPath))
        }
    }
}
