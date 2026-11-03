import SwiftUI

/// Alternate episode orderings (TVDB season types: Aired, DVD, Absolute, …), the Expo details
/// page's "Episode Order" option: picked from More Options, saved per series for the profile,
/// and the page reloaded in it. Episodes then carry their ordering (`Episode.numbering`) into
/// prequeue and source searches, so the server resolves "S01E02" in the same ordering.
extension DetailsView {
    /// Only series with more than one ordering offer the choice.
    var offersOrderings: Bool { !target.isMovie && orderings.count > 1 }

    var activeOrderingEntry: SeriesOrdering? {
        orderings.first { $0.type == (pickedOrdering ?? activeOrdering) }
    }

    var activeOrderingName: String {
        activeOrderingEntry?.name ?? String(localized: "Default")
    }

    /// The submenu under More Options. A non-default ordering turns off Trakt / Simkl sync for
    /// the series (its numbers no longer match theirs), which the header says, as Expo's
    /// picker warning does.
    @ViewBuilder
    var orderingMenu: some View {
        if offersOrderings {
            Divider()
            Menu {
                Section {
                    ForEach(orderings) { ordering in
                        Button { pickOrdering(ordering) } label: {
                            if ordering.type == activeOrderingEntry?.type {
                                Label(orderingLabel(ordering), systemImage: "checkmark")
                            } else {
                                Text(orderingLabel(ordering))
                            }
                        }
                    }
                } header: {
                    Text("Non-default orders pause watch-history sync for this show.")
                }
            } label: {
                Label("Episode Order: \(activeOrderingName)", systemImage: "list.number")
            }
        }
    }

    private func orderingLabel(_ ordering: SeriesOrdering) -> String {
        ordering.isOfficial == true ? "\(ordering.name) (Default)" : ordering.name
    }

    /// Shows the page in `ordering` straight away (asked for explicitly, so a failed save still
    /// applies for the visit), and saves it for the profile.
    func pickOrdering(_ ordering: SeriesOrdering) {
        guard ordering.type != activeOrderingEntry?.type else { return }
        pickedOrdering = ordering.type
        // Season numbers mean something else in the new ordering: start from Up Next's.
        selectedSeason = nil
        let tvdbID = title?.tvdbId ?? target.tvdbID.flatMap { Int($0) }
        Task {
            if let tvdbID {
                try? await APIClient.shared.setSeriesOrdering(tvdbID: tvdbID, seasonType: ordering.type)
            }
            await load()
        }
    }
}
