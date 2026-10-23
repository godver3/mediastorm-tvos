import Foundation

extension APIClient {
    /// The playback settings this client reads. Each is layered as the Expo app layers it:
    /// this device's override from `/api/clients/{id}/settings`, then the profile's settings
    /// (defaults already filled in by the server).
    struct PlaybackSettings {
        /// The next episode plays by itself once the credits start
        /// (`playback.creditsAutoSkip`, legacy `creditsDetection`).
        var creditsAutoSkip = false
        /// Streams start resolving as a details page opens (`playback.disablePrequeue` off).
        var prequeueOnOpen = true
        /// The Expo app's subtitle style (`playback.subtitle*`), which seeds this device's
        /// `SubtitleStyle` once; nil from servers that send none.
        var subtitleStyle: SubtitleStyle.Server?
        /// The details page plays the trailer behind the header (`playback.autoPlayTrailersTV`;
        /// on the device's own settings it is top-level).
        var autoPlayTrailers = false
    }

    func playbackSettings() async -> PlaybackSettings {
        struct Playback: Decodable {
            let creditsAutoSkip: Bool?
            let creditsDetection: Bool?
            let disablePrequeue: Bool?
            let autoPlayTrailersTV: Bool?
            /// The `subtitle*` fields of the same object.
            let style: SubtitleStyle.Server?
            var autoSkip: Bool? { creditsAutoSkip ?? creditsDetection }

            private enum CodingKeys: String, CodingKey { case creditsAutoSkip, creditsDetection, disablePrequeue, autoPlayTrailersTV }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                creditsAutoSkip = try c.decodeIfPresent(Bool.self, forKey: .creditsAutoSkip)
                creditsDetection = try c.decodeIfPresent(Bool.self, forKey: .creditsDetection)
                disablePrequeue = try c.decodeIfPresent(Bool.self, forKey: .disablePrequeue)
                autoPlayTrailersTV = try c.decodeIfPresent(Bool.self, forKey: .autoPlayTrailersTV)
                style = try? SubtitleStyle.Server(from: decoder)
            }
        }
        struct UserSettings: Decodable { let playback: Playback? }

        async let user: UserSettings? = try? await send("GET", "/api/users/\(Self.segment(profileID))/settings",
                                                        promptOnLock: false, timeout: 10)
        async let device: Playback? = try? await send("GET", "/api/clients/\(Self.segment(Config.clientID))/settings",
                                                      query: ["userId": profileID], promptOnLock: false, timeout: 10)
        let (u, d) = await (user?.playback, device)
        return PlaybackSettings(
            creditsAutoSkip: d?.autoSkip ?? u?.autoSkip ?? false,
            prequeueOnOpen: !(d?.disablePrequeue ?? u?.disablePrequeue ?? false),
            subtitleStyle: d?.style.map { $0.merged(over: u?.style) } ?? u?.style,
            autoPlayTrailers: d?.autoPlayTrailersTV ?? u?.autoPlayTrailersTV ?? false)
    }
}

extension APIClient {
    /// The menu tabs the profile shows (`display.navigationTabVisibility`), layered as the
    /// Expo app layers it: this device's override from `/api/clients/{id}/settings`, then
    /// the profile's (the server's defaults already filled in). Nil when neither answers.
    func navigationTabVisibility() async -> [String]? {
        struct Display: Decodable { let navigationTabVisibility: [String]? }
        struct UserSettings: Decodable { let display: Display? }
        struct Device: Decodable { let navigationTabVisibility: [String]? }

        async let user: UserSettings? = try? await send("GET", "/api/users/\(Self.segment(profileID))/settings",
                                                        promptOnLock: false, timeout: 10)
        async let device: Device? = try? await send("GET", "/api/clients/\(Self.segment(Config.clientID))/settings",
                                                    query: ["userId": profileID], promptOnLock: false, timeout: 10)
        let (u, d) = await (user?.display?.navigationTabVisibility, device?.navigationTabVisibility)
        // An empty list means unset, as in the Expo app's `toVisibilityMap`.
        return [d, u].lazy.compactMap { $0 }.first { !$0.isEmpty }
    }
}
