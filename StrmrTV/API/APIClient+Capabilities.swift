import AetherEngine
import Foundation

private let log = AppLog(category: "Capabilities")

extension APIClient {
    /// Reports the display's HDR / Dolby Vision support into this device's client settings
    /// (`adaptivePlayback.displayHdr` / `displayDv`), as the Expo app's
    /// `reportAdaptiveMeasurements` does, so adaptive playback leaves out releases the panel
    /// can't show. Runs only while the profile's (else the server's)
    /// `filtering.adaptivePlaybackEnabled` is on, and writes only when a value changed.
    ///
    /// The server replaces client settings whole, so the stored object is read and written back
    /// as raw JSON: every field this app doesn't model (admin overrides) survives the round trip.
    /// The device must be registered first; an unregistered client's settings read fails and
    /// nothing is written.
    func reportDisplayCapabilities() async {
        guard await adaptivePlaybackEnabled() else { return }
        let caps = AetherEngine.displayCapabilities
        let hdr = caps.supportsHDR
        // As in the Expo app, an HDR panel counts as Dolby Vision capable: the engine presents
        // Dolby Vision (Profile 5 included) on an HDR10-only panel too, so DV releases stay in.
        let dolbyVision = caps.supportsDolbyVision || hdr

        let path = "/api/clients/\(Self.segment(Config.clientID))/settings"
        let query = ["userId": profileID]
        do {
            let data = try await sendRaw("GET", path, query: query, promptOnLock: false, timeout: 10)
            var settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let stored = settings["adaptivePlayback"] as? [String: Any]
            if stored?["displayHdr"] as? Bool == hdr, stored?["displayDv"] as? Bool == dolbyVision { return }
            // Throughput is never stored here (it rides on searches), so the object is replaced.
            settings["adaptivePlayback"] = ["displayHdr": hdr, "displayDv": dolbyVision]
            try await sendRaw("PUT", path, query: query, jsonObject: settings, promptOnLock: false, timeout: 10)
            log.info("display reported hdr=\(hdr) dv=\(dolbyVision) (panel dv=\(caps.supportsDolbyVision))")
        } catch {
            log.error("display report failed: \(error.localizedDescription)")
        }
    }

    /// `filtering.adaptivePlaybackEnabled`: the profile's value, else the server's.
    func adaptivePlaybackEnabled() async -> Bool {
        struct Filtering: Decodable { let adaptivePlaybackEnabled: Bool? }
        struct Settings: Decodable { let filtering: Filtering? }
        async let user: Settings? = try? await send("GET", "/api/users/\(Self.segment(profileID))/settings",
                                                    promptOnLock: false, timeout: 10)
        async let server: Settings? = try? await send("GET", "/api/settings", timeout: 10)
        let (u, s) = await (user?.filtering?.adaptivePlaybackEnabled, server?.filtering?.adaptivePlaybackEnabled)
        return u ?? s ?? false
    }
}
