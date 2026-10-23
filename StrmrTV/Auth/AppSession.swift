import AVFoundation
import Foundation
import UIKit

/// Startup and account state: which server, whether signed in, which profile.
/// Drives `RootView`; `APIClient` does the transport.
@MainActor
final class AppSession: ObservableObject {
    static let shared = AppSession()

    enum Phase: Equatable {
        case starting
        case server
        case login
        case profiles
        case ready
        /// A stored session couldn't be checked (server unreachable); retryable.
        case unavailable(String)
    }

    @Published private(set) var phase: Phase = .starting
    @Published private(set) var serverURL: URL?
    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var profile: Profile?
    @Published private(set) var serverVersion: ServerVersion?
    /// Connected over iroh remote access (`serverURL` is then the loopback proxy).
    @Published private(set) var isRemote = false
    /// The server's custom logo (admin UI → Appearance & Branding), when one is uploaded.
    @Published private(set) var brandLogoURL: URL?
    /// Shown on the login screen after an involuntary sign-out.
    @Published var loginNotice: String?
    /// A request hit a locked profile; `RootView` asks for its PIN.
    @Published private(set) var pinChallenge: PinChallenge?

    struct PinChallenge: Identifiable, Equatable {
        let id = UUID()
        let profile: Profile
    }

    private var challengeContinuation: CheckedContinuation<Bool, Never>?
    private var challengeTask: (profileID: String, task: Task<Bool, Never>)?

    private let api = APIClient.shared
    private let defaults = UserDefaults.standard
    private enum Key {
        static let serverURL = "strmrtv.serverURL"
        static let lastProfileID = "strmrtv.lastProfileID"
        static let autoProfileID = "strmrtv.autoProfileID"
    }

    var username: String? { api.session?.username }
    var lastProfileID: String? { defaults.string(forKey: Key.lastProfileID) }
    /// "Use this profile automatically": opened at launch without the picker (or its PIN).
    var autoProfileID: String? { defaults.string(forKey: Key.autoProfileID) }
    /// Switching from Settings (rather than first pick) can be cancelled.
    var canCancelProfilePick: Bool { profile != nil }

    private init() {
        api.onSignedOut = { [weak self] in
            self?.loginNotice = String(localized: "Your session expired. Sign in again.")
            self?.phase = .login
        }
        api.onProfileLocked = { [weak self] id in await self?.unlockLockedProfile(id) ?? false }
        api.recoverTransport = { [weak self] in
            guard let self, self.isRemote else { return nil }
            try? await self.reconnectRemoteOrThrow()
            return self.serverURL
        }
        // The display can change while the app sleeps (another TV, a new output mode), so its
        // HDR / Dolby Vision support is reported again on wake and whenever tvOS says it changed.
        for name in [UIApplication.willEnterForegroundNotification, AVPlayer.eligibleForHDRPlaybackDidChangeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportDisplayCapabilities() }
            }
        }
        // A remote connection's path can die while the app sleeps; check it on wake.
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.reconnectRemote() }
        }
    }

    // MARK: Startup

    func start() async {
        #if DEBUG
        if DebugPrefill.resetSession { forgetEverything() }
        #endif
        if RemoteAccess.shared.pairing != nil {
            await startRemote()
        } else if let saved = defaults.url(forKey: Key.serverURL) {
            useServer(saved)
            if api.session != nil {
                await resumeSession()
            } else {
                phase = .login
            }
        } else {
            // Keychain items outlive an uninstall; a token without a server is stale.
            forgetEverything()
            phase = .server
        }
        #if DEBUG
        await autoSignInIfRequested()
        #endif
    }

    /// Re-checks a stored session by listing profiles, then opens the auto-select one.
    func resumeSession() async {
        phase = .starting
        if isRemote {
            do {
                try await reconnectRemoteOrThrow()
            } catch {
                phase = .unavailable(error.localizedDescription)
                return
            }
        }
        do {
            try await loadProfiles()
        } catch APIError.signedOut {
            return  // onSignedOut moved us to .login
        } catch {
            phase = .unavailable(error.localizedDescription)
            return
        }
        if let auto = profiles.first(where: { $0.id == autoProfileID }) {
            await activate(auto)
        } else if profiles.count == 1, let only = profiles.first, !only.requiresPin {
            await activate(only)
        } else {
            phase = .profiles
        }
    }

    // MARK: Server

    /// Validates the typed address and moves on to sign-in.
    func connect(to input: String) async throws {
        guard let url = ServerAddress.normalize(input) else {
            throw APIError.notReady(String(localized: "Enter a server address, like 192.168.1.10 or media.example.com."))
        }
        try await api.checkHealth(of: url)
        if isRemote { leaveRemote() }
        if url != serverURL {
            await api.logout()
            defaults.removeObject(forKey: Key.lastProfileID)
            defaults.removeObject(forKey: Key.autoProfileID)
        }
        useServer(url)
        defaults.set(url, forKey: Key.serverURL)
        phase = api.session == nil ? .login : .starting
        if api.session != nil { await resumeSession() }
    }

    /// A server found on the LAN: resolve its address, confirm with `/api/version`,
    /// then continue as if it had been typed.
    func connect(to discovered: DiscoveredServer) async throws {
        guard let url = await ServerBrowser.baseURL(for: discovered) else {
            throw APIError.notReady(String(localized: "Couldn't reach \(discovered.name). Enter its address below."))
        }
        _ = try await api.checkVersion(of: url)
        try await connect(to: url.absoluteString)
    }

    // MARK: Remote access

    /// Pairs over iroh with a connection code from the server's admin UI.
    func connect(code: String) async throws {
        let url = try await RemoteAccess.shared.pair(code: code)
        // A new pairing is a new server as far as the session goes.
        await api.logout()
        defaults.removeObject(forKey: Key.lastProfileID)
        defaults.removeObject(forKey: Key.autoProfileID)
        defaults.removeObject(forKey: Key.serverURL)
        isRemote = true
        api.remoteCredential = RemoteAccess.shared.pairing?.credential
        useServer(url)
        phase = .login
    }

    private func startRemote() async {
        phase = .starting
        isRemote = true
        api.remoteCredential = RemoteAccess.shared.pairing?.credential
        do {
            useServer(try await RemoteAccess.shared.connect())
        } catch {
            phase = .unavailable(error.localizedDescription)
            return
        }
        if api.session != nil { await resumeSession() } else { phase = .login }
    }

    /// The proxy again after sleep or a failure; its port can change, so the base URL follows.
    private func reconnectRemoteOrThrow() async throws {
        let url = try await RemoteAccess.shared.connect()
        if url != serverURL {
            serverURL = url
            api.baseURL = url
        }
    }

    private func reconnectRemote() async {
        guard isRemote else { return }
        try? await reconnectRemoteOrThrow()
    }

    private func leaveRemote() {
        RemoteAccess.shared.forget()
        isRemote = false
        api.remoteCredential = nil
    }

    func changeServer() {
        phase = .server
    }

    /// Back out of "Change Server" to wherever we were.
    func cancelServerChange() {
        guard serverURL != nil else { return }
        phase = profile != nil ? .ready : api.session != nil ? .profiles : .login
    }

    private func useServer(_ url: URL) {
        serverURL = url
        api.baseURL = url
        api.session = AuthSession.load()
        brandLogoURL = nil
        Task {
            serverVersion = await api.serverVersion()
        }
        Task {
            guard let path = await api.publicBranding()?.logoPath, serverURL == url else { return }
            brandLogoURL = URL(string: path, relativeTo: url)?.absoluteURL
        }
    }

    // MARK: Account

    func signIn(username: String, password: String) async throws {
        loginNotice = nil
        _ = try await api.login(username: username, password: password)
        try await loadProfiles()
        if profiles.count == 1, let only = profiles.first, !only.requiresPin {
            await activate(only)
        } else {
            phase = .profiles
        }
    }

    func signOut() async {
        cancelChallenge()
        await api.logout()
        TopShelfSync.clear()
        profile = nil
        profiles = []
        defaults.removeObject(forKey: Key.lastProfileID)
        defaults.removeObject(forKey: Key.autoProfileID)
        phase = .login
    }

    // MARK: Profiles

    func loadProfiles() async throws {
        let list = try await api.profiles()
        guard !list.isEmpty else {
            throw APIError.notReady(String(localized: "This account has no profiles. Add one in the web UI."))
        }
        profiles = list
    }

    /// Picks a profile, checking its PIN first when it has one, and remembers it for
    /// launch when `automatic`. Returns false for a wrong PIN.
    func select(_ candidate: Profile, pin: String? = nil, automatic: Bool = false) async throws -> Bool {
        if candidate.requiresPin {
            guard let pin, !pin.isEmpty, try await api.verifyPIN(pin, profileID: candidate.id) else { return false }
        }
        setAutoProfile(automatic ? candidate.id : nil)
        await activate(candidate)
        return true
    }

    func setAutoProfile(_ id: String?) {
        defaults.set(id, forKey: Key.autoProfileID)
    }

    func switchProfile() async {
        TopShelfSync.clear()
        phase = .profiles
        try? await loadProfiles()
    }

    func cancelProfilePick() {
        if profile != nil { phase = .ready }
    }

    private func activate(_ chosen: Profile) async {
        api.activate(profileID: chosen.id, profileName: chosen.name)
        profile = chosen
        defaults.set(chosen.id, forKey: Key.lastProfileID)
        phase = .ready
        // Registration ties this device to the profile for per-device settings and
        // Active Streams; it is not needed to browse, so a failure isn't fatal.
        do {
            try await api.registerClient(profileID: chosen.id)
        } catch {
            print("[AppSession] client registration failed: \(error.localizedDescription)")
        }
        reportDisplayCapabilities()
        LogUploader.shared.start()
    }

    /// Adaptive playback's display report (see `APIClient.reportDisplayCapabilities`); needs the
    /// device registered, so only once a profile is in use.
    private func reportDisplayCapabilities() {
        guard phase == .ready else { return }
        Task { await api.reportDisplayCapabilities() }
    }

    private func forgetEverything() {
        leaveRemote()
        defaults.removeObject(forKey: Key.serverURL)
        defaults.removeObject(forKey: Key.lastProfileID)
        defaults.removeObject(forKey: Key.autoProfileID)
        api.forgetSession()
        TopShelfSync.clear()
    }

    // MARK: Locked profile mid-flow

    /// `403 profile_locked` (server-enforced PINs; the unlock expired or was revoked):
    /// ask for the PIN over the current screen. Concurrent requests share one prompt.
    /// Returns true once unlocked; on cancel, goes back to the profile picker.
    private func unlockLockedProfile(_ id: String) async -> Bool {
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

    // MARK: Debug

    #if DEBUG
    /// `-StrmrAutoSignIn 1`: walk the flow with the optional `Secrets` values.
    private func autoSignInIfRequested() async {
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
    #endif
}
