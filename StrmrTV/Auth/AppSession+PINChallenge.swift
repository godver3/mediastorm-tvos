import Foundation

/// A locked profile met mid-flow.
extension AppSession {
    /// `403 profile_locked` (server-enforced PINs; the unlock expired or was revoked):
    /// ask for the PIN over the current screen. Concurrent requests share one prompt.
    /// Returns true once unlocked; on cancel, goes back to the profile picker.
    func unlockLockedProfile(_ id: String) async -> Bool {
        if let challengeTask {
            return challengeTask.profileID == id ? await challengeTask.task.value : false
        }
        // No prompt over the player (or before a profile is in use): the call fails.
        guard phase == .ready, !PlaybackCoordinator.shared.isPresentingPlayer,
              let locked = profiles.first(where: { $0.id == id }) ?? (profile?.id == id ? profile : nil)
        else { return false }
        let task = Task<Bool, Never> { @MainActor in
            await withCheckedContinuation { continuation in
                challengeContinuation = continuation
                pinChallenge = PinChallenge(profile: locked)
            }
        }
        challengeTask = (id, task)
        let unlocked = await task.value
        challengeTask = nil
        if !unlocked, id == profile?.id, phase == .ready { await switchProfile() }
        return unlocked
    }

    /// Checks a PIN entered for the current challenge; on success the prompt closes and
    /// the waiting requests retry.
    func verifyChallenge(pin: String) async -> PINVerification {
        guard let challenge = pinChallenge else { return .wrong }
        do {
            guard try await api.verifyPIN(pin, profileID: challenge.profile.id) else { return .wrong }
        } catch {
            return .failed(error.localizedDescription)
        }
        pinChallenge = nil
        finishChallenge(true)
        return .unlocked
    }

    func cancelChallenge() {
        pinChallenge = nil
        finishChallenge(false)
    }

    private func finishChallenge(_ unlocked: Bool) {
        challengeContinuation?.resume(returning: unlocked)
        challengeContinuation = nil
    }
}
