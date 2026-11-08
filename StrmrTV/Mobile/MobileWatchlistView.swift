#if os(iOS)
import SwiftUI

/// The Watchlist tab: the profile's watchlist as a list page (the Expo watchlist screen),
/// paged from the server with its sorts, Movies / Shows, watch-status and genre filters, the
/// A–Z index under a Name sort, a title filter and a random pick. Long press a poster for
/// the title actions, Remove from Watchlist among them.
struct MobileWatchlistView: View {
    var body: some View {
        MobileBrowseGrid(list: .watchlist)
    }
}
#endif
