import Foundation

#if DEBUG
extension AppSession {
    /// `-StrmrAutoSignIn 1`: walk the flow with the optional `Secrets` values.
    func autoSignInIfRequested() async {
        guard DebugPrefill.autoSignIn, let s = DebugPrefill.secrets else { return }
        do {
            if let code = DebugPrefill.pairCode, !isRemote { try await connect(code: code) }
            guard phase != .ready else { return }
            if phase == .server { try await connect(to: s.serverURL) }
            if phase == .login { try await signIn(username: s.username, password: s.password) }
            if phase == .profiles, let match = profiles.first(where: { $0.name == s.profileName }) {
                _ = try await select(match, pin: s.profilePIN)
            }
        } catch {
            print("[AppSession] debug auto sign-in failed: \(error.localizedDescription)")
        }
    }
}
#endif
