import UIKit

/// Coming back from the background, as the Expo app does: the profile picker comes up again
/// (server setting `display.alwaysShowProfileSelector`, on by default), and with it off a
/// PIN profile asks for its PIN again after five minutes away. Neither happens for the
/// "Use Automatically" profile, over the player, or after a moment away (under 2 s).
extension AppSession {
    static let resumePickerMinimumAway: TimeInterval = 2
    static let resumePINExpiry: TimeInterval = 5 * 60

    func observeBackgroundForResumeLock() {
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.backgroundedAt == nil { self.backgroundedAt = Date() }
            }
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyResumeLock() }
        }
    }

    /// Re-reads the server setting so the next resume decides without waiting on the network.
    func refreshResumeLockSetting() {
        struct Display: Decodable { let alwaysShowProfileSelector: Bool? }
        struct Settings: Decodable { let display: Display? }
        Task {
            guard let settings: Settings = try? await api.send("GET", "/api/settings", promptOnLock: false, timeout: 10)
            else { return }
            alwaysShowProfileSelector = settings.display?.alwaysShowProfileSelector ?? true
        }
    }

    private func applyResumeLock() {
        guard let since = backgroundedAt else { return }
        backgroundedAt = nil
        let away = Date().timeIntervalSince(since)
        guard phase == .ready, pinChallenge == nil, let current = profile, current.id != autoProfileID,
              !PlaybackCoordinator.shared.isPresentingPlayer
        else { return }

        if alwaysShowProfileSelector, profiles.count > 1, away > Self.resumePickerMinimumAway {
            print("[AppSession] resume after \(Int(away)) s: profile picker")
            profilePickRequired = current.requiresPin
            Task { await switchProfile() }
        } else if current.requiresPin, away >= Self.resumePINExpiry {
            print("[AppSession] resume after \(Int(away)) s: PIN for \(current.name)")
            // Cancel goes to the picker (`unlockLockedProfile`), which can't then be backed out of.
            profilePickRequired = true
            Task {
                if await unlockLockedProfile(current.id) { profilePickRequired = false }
            }
        }
        refreshResumeLockSetting()
    }
}
