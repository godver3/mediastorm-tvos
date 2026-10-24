import SwiftUI

/// Something the game page lets its tabs do. Any two are equal: an action only touches the
/// page's own state and scroll view, which last as long as the page, so handing a fresh one
/// down on each update changes nothing below.
struct SportsPageAction<Input>: Equatable {
    let perform: (Input) -> Void

    func callAsFunction(_ input: Input) { perform(input) }

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

/// A player's line in the Box Score: their side, their id and the line's category ("Batting").
struct SportsPlayerTarget: Equatable {
    let teamID: String
    let playerID: String
    let category: String
}

extension EnvironmentValues {
    /// Scrolls the game page to the view with this id, lined up by the anchor: the drive explorer
    /// fills the screen while the remote is in it, its list and the chosen drive side by side.
    @Entry var sportsPageScroll: SportsPageAction<(id: String, anchor: UnitPoint)>?

    /// Opens the Box Score on a player's line (Expo `onPlayerSelect`: the batter or pitcher on
    /// MLB's Overview); nil where the page can't.
    @Entry var sportsShowPlayer: SportsPageAction<SportsPlayerTarget>?
}
