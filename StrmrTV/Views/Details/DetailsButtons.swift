import SwiftUI

/// Which of the details page's secondary actions sit in the action row and which are listed in
/// More Options instead (Customize Buttons…, at the end of More). Play / Resume and More always
/// stay in the row, in a fixed order, so a hidden button only closes its gap. Kept on the
/// device, per profile; Manage Lists starts in More.
@MainActor
final class DetailsButtonsStore: ObservableObject {
    typealias Action = DetailsView.DetailsAction

    static let shared = DetailsButtonsStore()
    static let defaultInMore: Set<Action> = [.lists]

    enum Keys {
        /// Actions in More, by profile id (raw values).
        static let inMore = "detailsButtons.inMore"
    }

    private let defaults: UserDefaults
    @Published private var saved: [String: [String]]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        saved = defaults.dictionary(forKey: Keys.inMore) as? [String: [String]] ?? [:]
    }

    func inMore(profileID: String = APIClient.shared.profileID) -> Set<Action> {
        guard let raw = saved[profileID] else { return Self.defaultInMore }
        return Set(raw.compactMap(Action.init(rawValue:)))
    }

    func inRow(_ action: Action, profileID: String = APIClient.shared.profileID) -> Bool {
        !Action.customizable.contains(action) || !inMore(profileID: profileID).contains(action)
    }

    func setInRow(_ action: Action, _ shown: Bool, profileID: String = APIClient.shared.profileID) {
        guard Action.customizable.contains(action) else { return }
        var more = inMore(profileID: profileID)
        if shown { more.remove(action) } else { more.insert(action) }
        // In row order, so the stored list reads like the row.
        saved[profileID] = Action.customizable.filter(more.contains).map(\.rawValue)
        defaults.set(saved, forKey: Keys.inMore)
    }
}

extension DetailsView.DetailsAction {
    /// The actions Customize Buttons lists, in row order.
    static let customizable: [Self] = [.startOver, .versions, .chooseSource, .tracks, .trailer, .watchlist, .lists, .watched]

    var title: String {
        switch self {
        case .primary: String(localized: "Play")
        case .startOver: String(localized: "Start Over")
        case .versions: String(localized: "Versions")
        case .chooseSource: String(localized: "Choose Source")
        case .tracks: String(localized: "Audio & Subtitles")
        case .trailer: String(localized: "Trailer")
        case .watchlist: String(localized: "Watchlist")
        case .lists: String(localized: "Manage Lists")
        case .watched: String(localized: "Watch State")
        case .more: String(localized: "More Options")
        }
    }

    var symbol: String {
        switch self {
        case .primary: "play.fill"
        case .startOver: "arrow.counterclockwise"
        case .versions: "externaldrive"
        case .chooseSource: "magnifyingglass"
        case .tracks: "waveform"
        case .trailer: "film"
        case .watchlist: "plus"
        case .lists: "text.badge.checkmark"
        case .watched: "eye"
        case .more: "ellipsis"
        }
    }
}

/// Customize Buttons: one switch per secondary action, on for the row, off for More. Full
/// screen over the blurred page, like the other details pickers; Menu returns to the page.
struct DetailsButtonsSheet: View {
    @ObservedObject var store = DetailsButtonsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            Text("Details Buttons").font(.system(size: 52, weight: .bold))
            Text("Choose which buttons sit in the details page's row. The rest are listed in More Options; Play and More Options always stay. Saved on this Apple TV for this profile.")
                .font(.system(size: 26)).foregroundStyle(.secondary)
            Form {
                ForEach(DetailsView.DetailsAction.customizable, id: \.self) { action in
                    Toggle(action.title, isOn: Binding(get: { store.inRow(action) }, set: { store.setInRow(action, $0) }))
                }
            }
        }
        .frame(width: 1000)
        .padding(.top, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
    }
}

extension View {
    /// A caption under a focused action button, as Versions and Audio & Subtitles show.
    func focusCaption(_ text: String?, shown: Bool) -> some View {
        overlay(alignment: .bottom) {
            if shown, let text {
                Text(text)
                    .font(.system(size: 22, weight: .medium)).foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(y: 44)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// The primary button's resume progress, filled left to right as on the Expo button. The system
/// platter can't be filled and hides anything behind it, and the button style clips its label,
/// so the fill lies over the button: at rest a white wash added onto the grey platter (white,
/// like the cards' progress bars; white text stays white), focused a light shade over the white platter (black text stays black),
/// grown with the platter's focus lift.
private struct ResumeProgressFill: ViewModifier {
    /// How far the focused platter grows past the button's frame on each side.
    static let focusGrowth = 4.0

    let fraction: Double
    let focused: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if fraction > 0 {
                GeometryReader { geo in
                    Rectangle()
                        .fill(focused ? Color.black.opacity(0.14) : Color.white.opacity(0.22))
                        .blendMode(focused ? .normal : .plusLighter)
                        .frame(width: geo.size.width * min(fraction, 1))
                }
                .padding(focused ? -Self.focusGrowth : 0)
                .clipShape(Capsule())
                .animation(.easeOut(duration: 0.15), value: focused)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    func resumeProgressFill(_ fraction: Double, focused: Bool) -> some View {
        modifier(ResumeProgressFill(fraction: fraction, focused: focused))
    }
}
