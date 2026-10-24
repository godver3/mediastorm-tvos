import Foundation

/// Resume Multiscreen, and saving what it resumes: the screens' channels are saved on this
/// device whenever two or more are on screen (`MultiscreenResume`). Resume tunes the first two
/// at once, then adds the rest one at a time behind the provider's capacity, as Expo's
/// `restoreExtras` does, after the load warning if this device has never shown it.
extension MultiscreenController {
    func restore(_ selection: MultiscreenResume.Selection) {
        let channels = Array(selection.channels.prefix(MultiscreenSession.maxScreens))
        pendingAudio = channels.indices.contains(selection.audioIndex) ? channels[selection.audioIndex] : nil
        let first = channels.prefix(2).enumerated().map { session.tune($0.offset, to: $0.element) }
        session.focus(0)
        pendingExtras = Array(channels.dropFirst(2))
        guard !pendingExtras.isEmpty else { return }
        restoring = true
        Task {
            // The first two hold their connections before the extras' capacity checks count them.
            for tune in first { await tune.value }
            guard !finished, !pendingExtras.isEmpty else { return }
            if resume.warningShown { restoreExtras() } else { showWarning() }
        }
    }

    /// Adds Resume's remaining screens, stopping at the first one the provider has no room for.
    func restoreExtras() {
        let extras = pendingExtras
        pendingExtras = []
        selection += 1
        let generation = selection
        Task {
            defer {
                restoring = false
                saveSelection()
            }
            for channel in extras where session.index(of: channel) == nil {
                do {
                    let usage = try await api.liveUsage(sourceID: channel.sourceId)
                    guard generation == selection, !finished else { return }
                    guard usage.hasCapacity else {
                        exitError = String(localized: "Stream limit reached. Remaining screens were not added.")
                        controlsOpen = true
                        return
                    }
                } catch {
                    guard generation == selection, !finished else { return }
                    exitError = String(localized: "Unable to check stream capacity. Remaining screens were not added.")
                    controlsOpen = true
                    return
                }
                await session.tune(slots.count, to: channel).value
            }
        }
    }

    /// Resume's audible channel, once its screen plays.
    func listenToResumedAudio() {
        guard let channel = pendingAudio, let index = session.index(of: channel), slots[index].source != nil else { return }
        pendingAudio = nil
        session.listen(index)
    }

    /// The screens' channels in screen order, saved for Resume when there are two or more.
    func saveSelection() {
        guard !restoring, !finished else { return }
        let occupied = slots.indices.filter { slots[$0].channel != nil }
        guard occupied.count >= 2 else { return }
        let audio = occupied.firstIndex(of: session.audioIndex) ?? 0
        resume.save(.init(channels: occupied.compactMap { slots[$0].channel }, audioIndex: audio))
    }
}
