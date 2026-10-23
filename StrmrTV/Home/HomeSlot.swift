import Foundation

/// A place on Home: a row of cards, or the place a row holds while it loads or after it
/// failed with nothing to show.
enum HomeSlot: Identifiable, Equatable {
    case shelf(HomeShelf)
    case loading(id: String, title: String)
    case failed(id: String, title: String)

    var id: String {
        switch self {
        case let .shelf(shelf): shelf.id
        case let .loading(id, _), let .failed(id, _): id
        }
    }
    var isLoading: Bool { if case .loading = self { true } else { false } }
}
