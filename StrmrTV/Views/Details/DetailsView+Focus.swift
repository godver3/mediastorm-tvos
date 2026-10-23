import SwiftUI

/// Focus between the page's rows (`DetailsView.DetailsFocus`).
extension DetailsView {
    // MARK: Row focus

    /// Where focus enters a row from another row. Actions always start at Play; seasons and
    /// episodes start at the current one, then at whichever was last focused there.
    func entry(_ row: Row) -> DetailsFocus? {
        switch row {
        case .overview: return .overview
        case .actions: return .action(.primary)
        case .immersive: return .immersive
        case .seasons:
            let remembered = lastSeasonChip.flatMap { n in visibleSeasons.contains { $0.number == n } ? n : nil }
            return (remembered ?? currentSeason?.number).map(DetailsFocus.season)
        case .episodes:
            return currentSeason.flatMap(episodeEntry).map(DetailsFocus.episode)
        case .related(let row):
            let ids = relatedIDs(row)
            let id = lastRelated[row].flatMap { ids.contains($0) ? $0 : nil } ?? ids.first
            return id.map { .related(row, $0) }
        }
    }

    /// The episode last focused in `season`, else the one Play targets, else the first.
    func episodeEntry(_ season: Season) -> String? {
        if let id = lastEpisode[season.number], season.episodes.contains(where: { $0.id == id }) { return id }
        if let ep = primaryEpisode, season.episodes.contains(where: { $0.id == ep.id }) { return ep.id }
        return season.episodes.first?.id
    }

    /// Up / Down between rows lands on the row's entry rather than the geometrically nearest
    /// item; moves within a row are remembered for the next return.
    func steerFocus(from old: DetailsFocus?, to new: DetailsFocus?) {
        // Out of the immersive catcher, focus goes back to where it was.
        guard let new else { return }
        focusInHeader = Self.isHeader(new.row)
        guard old != .immersive else { return }
        if let old, old.row != new.row, let target = entry(new.row), target != new {
            focus = target
            return
        }
        switch new {
        case .overview, .action, .immersive: break
        case .season(let number): lastSeasonChip = number
        case .episode(let id):
            if let season = currentSeason?.number { lastEpisode[season] = id }
        case .related(let row, let id): lastRelated[row] = id
        }
    }
}
