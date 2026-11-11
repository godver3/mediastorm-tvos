import SwiftUI

/// A watched / unwatched change to many episodes at once, held until the user confirms it.
/// One press can otherwise mark thousands of episodes (a long-running soap's whole run), so
/// every whole-show choice asks first, a single season asks once it reaches
/// `seasonThreshold` episodes, and a single episode never asks.
struct BulkWatchChange: Identifiable {
    enum Extent: Equatable {
        /// Every episode of the show.
        case wholeShow
        /// Every episode except the given (most recent) season.
        case wholeShowExcept(season: Int)
        /// One season, by its display name ("Season 3", "Specials").
        case season(String)
    }

    static let seasonThreshold = 50

    let id = UUID()
    let watched: Bool
    let count: Int
    let seriesName: String
    let extent: Extent
    let perform: () -> Void

    static func needsConfirmation(_ extent: Extent, count: Int) -> Bool {
        switch extent {
        case .wholeShow, .wholeShowExcept: true
        case .season: count >= seasonThreshold
        }
    }

    var title: String {
        let episodes = count == 1 ? String(localized: "1 episode") : String(localized: "\(count.formatted()) episodes")
        return watched ? String(localized: "Mark \(episodes) watched?") : String(localized: "Mark \(episodes) unwatched?")
    }

    var message: String {
        let subject: String
        switch extent {
        case .wholeShow:
            subject = watched ? String(localized: "Every aired episode of \(seriesName)")
                : String(localized: "Every episode of \(seriesName)")
        case .wholeShowExcept(let season):
            subject = watched ? String(localized: "Every aired episode of \(seriesName) except Season \(season)")
                : String(localized: "Every episode of \(seriesName) except Season \(season)")
        case .season(let name):
            subject = watched ? String(localized: "Every aired episode in \(name) of \(seriesName)")
                : String(localized: "Every episode in \(name) of \(seriesName)")
        }
        return watched
            ? String(localized: "\(subject) will be marked watched. Episodes you haven't played won't appear in watch history.")
            : String(localized: "\(subject) will be marked unwatched, clearing their watched state.")
    }

    var confirmLabel: String { watched ? String(localized: "Mark Watched") : String(localized: "Mark Unwatched") }
}

extension View {
    /// Presents `change` for confirmation; confirming runs its `perform`.
    func bulkWatchConfirmation(_ change: Binding<BulkWatchChange?>) -> some View {
        confirmationDialog(change.wrappedValue?.title ?? "",
                           isPresented: Binding(get: { change.wrappedValue != nil },
                                                set: { if !$0 { change.wrappedValue = nil } }),
                           titleVisibility: .visible, presenting: change.wrappedValue) { pending in
            Button(pending.confirmLabel, role: pending.watched ? nil : .destructive) { pending.perform() }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.message)
        }
    }
}
