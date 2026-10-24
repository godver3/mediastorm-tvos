import CoreGraphics
import Foundation

/// The screen geometry and the remote over the tiles: arrows move between tiles by
/// `MultiscreenLayout.neighbor` (handled here, not by focus search over absolutely placed
/// tiles), Select listens or enlarges, a long Select opens the control bar, and Menu backs
/// out one step at a time.
extension MultiscreenController {
    static let gap: CGFloat = 12
    static let dockHeight: CGFloat = 280
    static let footerHeight: CGFloat = 48
    /// Clear of the TV's overscan.
    static let margin = CGSize(width: 48, height: 32)

    /// Where the tiles go in a screen of `size`, above the control bar while it is open.
    func frames(in size: CGSize) -> [Int: CGRect] {
        let bottom = controlsOpen ? Self.dockHeight : Self.footerHeight + Self.margin.height
        let area = CGSize(width: max(1, size.width - Self.margin.width * 2),
                          height: max(1, size.height - Self.margin.height - bottom - 16))
        return MultiscreenLayout.frames(visibleIDs, expanded: expanded, size: area, gap: Self.gap)
            .mapValues { $0.offsetBy(dx: Self.margin.width, dy: Self.margin.height) }
    }

    /// An arrow on the tiles: to the neighbouring tile, or (down, with none below) the control bar.
    func move(_ direction: MultiscreenDirection, in size: CGSize) {
        reveal()
        if let next = MultiscreenLayout.neighbor(frames(in: size), of: focused, direction) {
            session.focus(next)
        } else if direction == .down {
            controlsOpen = true
        }
    }

    /// Select on a tile: the control bar when it isn't playing, else listen, else enlarge.
    func select() {
        reveal()
        let slot = focusedSlot
        if !slot.isPlaying {
            controlsOpen = true
        } else if session.audioIndex != focused {
            session.listen(focused)
        } else {
            expanded = focused
        }
    }

    func longSelect() {
        reveal()
        controlsOpen = true
    }

    /// Menu: a dialog, then the control bar, then the enlarged tile, then out of multiscreen.
    /// (The picker handles its own.)
    func back() {
        reveal()
        if dialog == .warning {
            dialog = nil
            controlsOpen = true
        } else if dialog != nil {
            dialog = nil
        } else if controlsOpen {
            controlsOpen = false
        } else if expanded != nil {
            expanded = nil
        } else {
            exit()
        }
    }

    var footerHint: String {
        if exiting { return String(localized: "Releasing streams…") }
        let ok = focused == session.audioIndex ? String(localized: "Enlarge") : String(localized: "Listen")
        if controlsOpen { return String(localized: "Arrow keys: Choose screen · OK \(ok) · ↑ / Back: Return to video") }
        let back = expanded != nil ? String(localized: "Equal tiles") : String(localized: "Guide")
        return String(localized: "Arrow keys: Choose screen · OK \(ok) · Hold OK: Controls · Back \(back)")
    }
}
