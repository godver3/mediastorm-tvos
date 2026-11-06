import Foundation

extension APIClient {
    /// The card badges the profile shows (`display.badgeVisibility`: watchProgress,
    /// releaseStatus, watchState, unwatchedCount), as the Expo app reads them: the profile's
    /// settings (the server merges its global value in when the profile sets none), else the
    /// server's own settings. Nil when neither answers.
    func badgeVisibility() async -> [String]? {
        struct Display: Decodable { let badgeVisibility: [String]? }
        struct Settings: Decodable { let display: Display? }

        async let user: Settings? = try? await send("GET", "/api/users/\(Self.segment(profileID))/settings",
                                                    promptOnLock: false, timeout: 10)
        async let server: Settings? = try? await send("GET", "/api/settings", promptOnLock: false, timeout: 10)
        if let values = await user?.display?.badgeVisibility { return values }
        return await server?.display?.badgeVisibility
    }
}
