import Combine
import Foundation
import UIKit

/// How multiscreen was opened.
enum MultiscreenEntry {
    /// From the Live tab: pick the first two channels.
    case pick
    /// From the full-screen player's HLS session, which screen 1 takes over as it is.
    case session(LiveChannel, url: URL, sessionID: String)
    /// From the full-screen player's direct stream: screen 1 opens the channel again over HLS.
    case tune(LiveChannel)
    /// The Live tab's Resume Multiscreen: this device's last selection for the profile.
    case resume(MultiscreenResume.Selection)
}

/// The server side of a tile: the provider's capacity is checked before every start.
@MainActor
struct MultiscreenAPITransport: MultiscreenTransport {
    func start(_ channel: LiveChannel) async throws -> (sessionID: String?, url: URL?) {
        let usage = try await APIClient.shared.liveUsage(sourceID: channel.sourceId)
        guard usage.hasCapacity else { throw APIError.notReady("Provider connection limit reached") }
        return try await APIClient.shared.startLiveHLS(channel)
    }

    func stop(_ sessionID: String) async throws {
        try await APIClient.shared.stopLiveSessionStrict(sessionID)
    }
}

/// Multiscreen's screen state around the `MultiscreenSession`: the tile players, the enlarged
/// tile, the control bar, dialogs, the channel picker, the auto-hiding overlay, the tiles'
/// now / next, and leaving. Remote handling is in `MultiscreenController+Remote.swift`.
@MainActor
final class MultiscreenController: ObservableObject {
    enum Dialog: Equatable {
        /// Before a third screen, the first time only on this device.
        case warning
        /// No capacity for `channel`: replace a screen with it, or cancel.
        case replacement(LiveChannel)
        /// Why a screen can't be added.
        case notice(String)
    }

    struct Picker: Equatable {
        /// Picking for a new screen rather than changing the focused one's channel.
        var adding: Bool
    }

    static let hudTimeout: TimeInterval = 5

    let session: MultiscreenSession
    private(set) var players: [Int: MultiscreenTilePlayer] = [:]

    @Published var expanded: Int?
    @Published var controlsOpen = false
    @Published var dialog: Dialog?
    @Published private(set) var picker: Picker?
    @Published private(set) var overlayVisible = true
    @Published private(set) var exiting = false
    @Published var exitError: String?
    @Published private(set) var nowNext: [String: EPGNowPlaying] = [:]
    /// Set once multiscreen has closed; the host dismisses on it.
    @Published private(set) var finished = false

    /// Still choosing the first two channels: backing out of the picker leaves multiscreen.
    private(set) var initialSetup: Bool
    private let fromPlayer: Bool
    let resume: MultiscreenResume
    /// Resume's third and fourth channels, added after the first two (and the warning).
    var pendingExtras: [LiveChannel] = []
    /// Resume's audible channel, listened to once its screen plays.
    var pendingAudio: LiveChannel?
    /// Resume is still adding screens: the half-restored selection isn't saved over the whole.
    var restoring = false
    /// What saving compares against: the last save, or what a resume ended with, so a resume
    /// cut short (Cancel, the stream limit) keeps the saved selection until the screens change.
    var savedBaseline: MultiscreenResume.Selection?
    private var selecting = false
    /// Bumped to drop a capacity check still in flight when the picker goes away.
    var selection = 0
    private var overlayTimer: Timer?
    private var epgTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var appActive = true
    let api = APIClient.shared
    private let log = AppLog(category: "multiscreen")

    init(entry: MultiscreenEntry, transport: MultiscreenTransport = MultiscreenAPITransport(),
         resume: MultiscreenResume = .shared) {
        session = MultiscreenSession(transport: transport)
        self.resume = resume
        initialSetup = true
        picker = Picker(adding: true)
        switch entry {
        case .pick:
            fromPlayer = false
        case let .session(channel, url, sessionID):
            fromPlayer = true
            session.adopt(channel, url: url, sessionID: sessionID)
            session.focus(1)
        case let .tune(channel):
            fromPlayer = true
            session.tune(0, to: channel)
            session.focus(1)
        case .resume:
            fromPlayer = false
            initialSetup = false
            picker = nil
        }
        session.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.sessionChanged() }
            .store(in: &cancellables)
        let center = NotificationCenter.default
        center.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.appActive = false; self?.sessionChanged() }
            .store(in: &cancellables)
        center.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.appActive = true; self?.sessionChanged() }
            .store(in: &cancellables)
        sessionChanged()
        reveal()
        if case let .resume(selection) = entry { restore(selection) }
    }

    /// The picker's pick, kept so the Live views see the same one on every update.
    private(set) lazy var pickAction = LiveChannelPick { [weak self] channel in self?.choose(channel) }

    var slots: [MultiscreenSlot] { session.slots }
    var focused: Int { session.focusedIndex }
    var focusedSlot: MultiscreenSlot { session.slots[session.focusedIndex] }

    /// The slots on screen: those with a channel (or tuning one), else the first two, empty.
    var visibleIDs: [Int] {
        let occupied = session.occupied
        return occupied.isEmpty ? [0, 1] : occupied
    }

    func player(_ index: Int) -> MultiscreenTilePlayer {
        if let player = players[index] { return player }
        let player = MultiscreenTilePlayer()
        player.onFailure = { [weak self] source in self?.session.fail(index, source: source) }
        players[index] = player
        return player
    }

    var pickerTitle: String {
        guard let picker else { return "" }
        if !picker.adding { return String(localized: "Choose channel · Screen \(focused + 1)") }
        if fromPlayer || !initialSetup { return String(localized: "Add channel") }
        return focused == 0 ? String(localized: "Choose first channel") : String(localized: "Choose second channel")
    }

    /// The overlay stays up for `hudTimeout` after any key.
    func reveal() {
        overlayVisible = true
        overlayTimer?.invalidate()
        overlayTimer = Timer.scheduledTimer(withTimeInterval: Self.hudTimeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.overlayVisible = false }
        }
    }

    // MARK: Actions

    func addScreen() {
        let occupied = session.occupied.count
        if occupied >= MultiscreenSession.maxScreens {
            controlsOpen = false
            dialog = .notice(String(localized: "Multiscreen shows up to \(MultiscreenSession.maxScreens) screens. Remove one to add another."))
        } else if occupied >= 2, !resume.warningShown {
            controlsOpen = false
            showWarning()
        } else {
            openPicker(adding: true)
        }
    }

    func showWarning() {
        resume.warningShown = true
        dialog = .warning
    }

    func acceptWarning() {
        dialog = nil
        if pendingExtras.isEmpty { openPicker(adding: true) } else { restoreExtras() }
    }

    /// Cancel on the warning, or the replacement dialog: back to the control bar.
    func dismissDialog() {
        let wasWarning = dialog == .warning
        dialog = nil
        if wasWarning {
            if pendingExtras.isEmpty {
                controlsOpen = true
            } else {
                pendingExtras = []
                finishRestoring()
            }
        }
    }

    func changeChannel() { openPicker(adding: false) }

    func retry() {
        let index = focused
        guard let channel = slots[index].channel else { return }
        controlsOpen = false
        session.tune(index, to: channel)
    }

    func remove() {
        let index = focused
        controlsOpen = false
        Task {
            await session.remove(index).value
            guard slots[index].channel == nil else { return }
            let remaining = slots.firstIndex { $0.channel != nil } ?? 0
            session.focus(remaining)
            let left = slots.filter { $0.channel != nil }.count
            expanded = left == 1 && slots[remaining].source != nil ? remaining : nil
        }
    }

    func equalTiles() {
        expanded = nil
        controlsOpen = false
    }

    /// The control bar's Enlarge, while the tiles are equal: the focused screen, if it plays.
    func enlarge() {
        guard focusedSlot.isPlaying else { return }
        expanded = focused
        controlsOpen = false
    }

    func replace(_ index: Int, with channel: LiveChannel) {
        dialog = nil
        expanded = nil
        session.focus(index)
        session.tune(index, to: channel)
    }

    private func openPicker(adding: Bool) {
        controlsOpen = false
        exitError = nil
        picker = Picker(adding: adding)
    }

    /// Menu in the picker: back to the screens, or out of multiscreen while the first two are
    /// still being chosen.
    func closePicker() {
        selection += 1
        selecting = false
        let adding = picker?.adding == true
        picker = nil
        reveal()
        if initialSetup, adding, slots.count > 1, slots[1].channel == nil, !slots[1].loading { exit() }
    }

    /// A channel picked in the picker: a new screen (after a capacity check), or the focused
    /// screen's new channel. A channel already on screen just focuses it.
    func choose(_ channel: LiveChannel) {
        guard let picker, !selecting else { return }
        if let duplicate = session.index(of: channel) {
            if initialSetup, picker.adding, slots[1].channel == nil, !slots[1].loading { return }
            session.focus(duplicate)
            self.picker = nil
            return
        }
        let empty = slots.indices.first { !slots[$0].isOccupied }
        let target = picker.adding ? (empty ?? slots.count) : focused
        guard target < MultiscreenSession.maxScreens else {
            self.picker = nil
            dialog = .notice(String(localized: "Multiscreen shows up to \(MultiscreenSession.maxScreens) screens. Remove one to add another."))
            return
        }
        selection += 1
        let generation = selection
        selecting = true
        Task {
            defer { if generation == selection { selecting = false } }
            if picker.adding {
                // Checked before a slot is added: a refused or failed check leaves the screens alone.
                do {
                    let usage = try await api.liveUsage(sourceID: channel.sourceId)
                    guard generation == selection else { return }
                    guard usage.hasCapacity else {
                        self.picker = nil
                        dialog = .replacement(channel)
                        return
                    }
                } catch {
                    guard generation == selection else { return }
                    exitError = String(localized: "Unable to check stream capacity. Retry before adding a screen.")
                    return
                }
            }
            session.tune(target, to: channel)
            session.focus(target)
            if initialSetup, picker.adding, target == 0, slots.count > 1, slots[1].channel == nil {
                session.focus(1)
            } else {
                initialSetup = false
                reveal()
                expanded = nil
                self.picker = nil
            }
        }
    }

    /// Releases every stream, then closes; a failed release stays with the error and the
    /// control bar so Guide can retry.
    func exit() {
        guard !exiting else { return }
        selection += 1
        selecting = false
        exiting = true
        Task {
            defer { exiting = false }
            do {
                try await session.close()
                shutdown()
                finished = true
            } catch {
                log.error("multiscreen release failed")
                exitError = String(localized: "Unable to release all streams. Select Exit to retry.")
                picker = nil
                controlsOpen = true
            }
        }
    }

    /// Stops every player (also when the host goes away without `exit`).
    func shutdown() {
        overlayTimer?.invalidate()
        epgTask?.cancel()
        cancellables.removeAll()
        players.values.forEach { $0.shutdown() }
        players = [:]
    }

    // MARK: Session changes

    /// Hands each tile its source, audio and pause state, and refreshes the tiles' guide data
    /// when their channels change.
    private func sessionChanged() {
        // objectWillChange fires before the change lands.
        DispatchQueue.main.async { [weak self] in
            guard let self, !finished else { return }
            for (index, slot) in slots.enumerated() {
                guard slot.source != nil || players[index] != nil else { continue }
                let player = player(index)
                player.play(slot.source)
                player.setAudible(session.audioIndex == index)
                player.setActive(appActive && slot.isPlaying)
            }
            listenToResumedAudio()
            saveSelection()
            refreshGuideIfNeeded()
            objectWillChange.send()
        }
    }

    private var guideKeys: [String] = []

    private func refreshGuideIfNeeded() {
        let keys = slots.compactMap { $0.channel?.tvgId }.filter { !$0.isEmpty }
        guard keys != guideKeys else { return }
        guideKeys = keys
        epgTask?.cancel()
        guard !keys.isEmpty else { return }
        epgTask = Task { [weak self] in
            while !Task.isCancelled {
                if let entries = try? await APIClient.shared.epgNow(keys) {
                    for entry in entries { self?.nowNext[entry.channelId] = entry }
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}
