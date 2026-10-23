import Foundation

/// The long-press / details actions, with the Expo app's toasts. Each one re-reads what it
/// changed and posts `titleStateChanged` (and `continueWatchingChanged` where the row
/// changes), so Home, the Lists tab and open grids reload through their usual paths.
extension TitleStateStore {
    /// Hidden from this profile: the server drops it from Home rows and lists.
    func hide(_ target: DetailsTarget) async {
        do {
            let item = try await api.hide(target)
            hidden.removeAll { $0.id == item.id && $0.mediaType == item.mediaType }
            hidden.insert(item, at: 0)
            log.notice("hid \(item.mediaType) \(item.id) (\(target.name))")
            show(toast: String(localized: "Hidden from this profile"))
            changed(continueWatching: true)
        } catch {
            log.error("hide \(target.titleID) failed: \(error.localizedDescription)")
            show(toast: String(localized: "Failed to hide item"))
        }
    }

    func unhide(_ target: DetailsTarget) async {
        guard let item = hiddenItem(target) else { return }
        await unhide(item)
    }

    func unhide(_ item: HiddenItem) async {
        do {
            try await api.unhide(mediaType: item.mediaType, id: item.id)
            hidden.removeAll { $0.id == item.id && $0.mediaType == item.mediaType }
            log.notice("unhid \(item.mediaType) \(item.id)")
            show(toast: String(localized: "Unhidden"))
            changed(continueWatching: true)
        } catch {
            log.error("unhide \(item.id) failed: \(error.localizedDescription)")
            show(toast: String(localized: "Failed to unhide item"))
        }
    }

    /// Parks a Continue Watching title in the Set Aside list (made on first use).
    func addToSetAside(_ target: DetailsTarget) async {
        do {
            let listID = try await ensureSetAsideList()
            let item = try await api.addToCustomList(id: listID, target.watchlistUpsert)
            setAside.removeAll { $0.id == item.id && $0.mediaType == item.mediaType }
            setAside.insert(item, at: 0)
            log.notice("set aside \(item.mediaType) \(item.id) in list \(listID)")
            show(toast: String(localized: "Added to Set Aside"))
            changed(continueWatching: true)
        } catch {
            log.error("set aside \(target.titleID) failed: \(error.localizedDescription)")
            show(toast: String(localized: "Failed to add to Set Aside"))
        }
    }

    func removeFromSetAside(_ target: DetailsTarget) async {
        await refreshSetAside()
        guard let listID = setAsideListID, let item = setAsideItem(target) else { return }
        do {
            try await api.removeFromCustomList(id: listID, mediaType: item.mediaType, itemID: item.id)
            setAside.removeAll { $0.id == item.id && $0.mediaType == item.mediaType }
            log.notice("removed \(item.mediaType) \(item.id) from Set Aside")
            show(toast: String(localized: "Removed from Set Aside"))
            changed(continueWatching: true)
        } catch {
            log.error("remove from Set Aside \(target.titleID) failed: \(error.localizedDescription)")
            show(toast: String(localized: "Failed to remove from Set Aside"))
        }
    }

    /// Drops a title from Continue Watching until it is played again.
    func hideFromContinueWatching(_ target: DetailsTarget) async {
        let id = continueWatchingItem(target)?.seriesId ?? target.titleID
        do {
            try await api.hideFromContinueWatching(seriesID: id)
            continueWatching.removeAll { $0.seriesId == id }
            log.notice("hid \(id) from Continue Watching")
            show(toast: String(localized: "Removed from Continue Watching"))
            changed(continueWatching: false)  // the API call posted the row's own notice
        } catch {
            log.error("hide \(id) from Continue Watching failed: \(error.localizedDescription)")
            show(toast: String(localized: "Failed to remove from Continue Watching"))
        }
    }

    func setWatched(_ watched: Bool, movie target: DetailsTarget) async {
        do {
            try await api.setWatched(watched, movie: target)
            log.notice("marked \(target.titleID) \(watched ? "watched" : "unwatched")")
            await refreshWatched()
            show(toast: watched ? String(localized: "Marked as watched") : String(localized: "Marked as unwatched"))
            changed(continueWatching: true)
        } catch {
            log.error("mark \(target.titleID) watched=\(watched) failed: \(error.localizedDescription)")
            show(toast: String(localized: "Failed to update watched state"))
        }
    }

    /// After a series' episodes were marked from the watch-state screen.
    func seriesWatchStateChanged() async {
        await refreshWatched()
        changed(continueWatching: true)
    }

    private func ensureSetAsideList() async throws -> String {
        let lists = try await api.customLists()
        if let list = lists.first(where: \.isSetAside) {
            setAsideListID = list.id
            return list.id
        }
        let created = try await api.createCustomList(name: Self.setAsideListName)
        log.notice("created the Set Aside list \(created.id)")
        setAsideListID = created.id
        return created.id
    }

    private func changed(continueWatching row: Bool) {
        NotificationCenter.default.post(name: .titleStateChanged, object: nil)
        if row { NotificationCenter.default.post(name: .continueWatchingChanged, object: nil) }
        Task { await refreshContinueWatching() }
    }
}
