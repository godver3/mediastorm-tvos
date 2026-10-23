import Foundation

/// One source's health check with its tracks, as the Expo manual picker asks for them on a
/// long press (`useManualHealthChecks.checkHealth(result, probeForTracks: true)`).
struct SourceTrackProbe {
    /// Healthy (usenet) or cached (debrid).
    let playable: Bool
    let audio: [ProbedAudioTrack]
    let subtitles: [ProbedSubtitleTrack]
    /// Debrid: the server is still probing in the background; ask again shortly.
    let tracksLoading: Bool
    let error: String?
}

extension APIClient {
    /// Usenet (and anything not debrid, as Expo treats it): `POST /api/usenet/health` with
    /// `probeForTracks`, which ffprobes the file synchronously once it is healthy. Debrid:
    /// `POST /api/debrid/cached` with `verifyUncached`, whose tracks may arrive on a later call
    /// (`tracksLoading`).
    func probeTracks(_ result: SourceResult) async throws -> SourceTrackProbe {
        struct Response: Decodable {
            let healthy: Bool?
            let cached: Bool?
            let status: String?
            let errorMessage: String?
            let audioTracks: [ProbedAudioTrack]?
            let subtitleTracks: [ProbedSubtitleTrack]?
            let trackProbeError: String?
            let tracksLoading: Bool?
        }
        let isDebrid = result.serviceType.lowercased() == "debrid"
        let response: Response
        if isDebrid {
            response = try await send("POST", "/api/debrid/cached", jsonObject: [
                "result": result.raw, "quickOnly": false, "verifyUncached": true,
            ], timeout: 90)
        } else {
            response = try await send("POST", "/api/usenet/health", jsonObject: [
                "result": result.raw, "probeForTracks": true, "profileId": profileID,
            ], timeout: 90)
        }
        let playable = isDebrid ? (response.cached ?? false) : (response.healthy ?? false)
        var error = response.trackProbeError.flatMap { $0.isEmpty ? nil : $0 }
        if !playable {
            let status = (response.status ?? "").replacingOccurrences(of: "_", with: " ")
            error = response.errorMessage ?? (isDebrid ? "Not cached" : "Unhealthy\(status.isEmpty ? "" : " (\(status))")")
        }
        return SourceTrackProbe(playable: playable, audio: response.audioTracks ?? [],
                                subtitles: response.subtitleTracks ?? [],
                                tracksLoading: isDebrid && playable && (response.tracksLoading ?? false),
                                error: error)
    }
}
