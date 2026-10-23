import SwiftUI

/// A request for the guide or grid to take focus back from the controls above it.
///
/// Menu pressed inside the guide or grid moves focus up to the control it last left from instead of
/// leaving the tab (Menu on the controls then behaves as usual). Pressing down from the
/// controls asks for `.enter`: back to the cell that had focus before Menu. Picking a
/// category leaves focus on the picker; down then enters the new list at its top.
enum LiveContentFocus: Equatable {
    /// Down pressed on the controls: back to the cell Menu left from, if Menu sent focus up.
    case enter
}

extension View {
    /// Menu-to-controls and the way back for a focusable list of `ID`s (see `LiveContentFocus`).
    /// `match` finds a remembered cell in the list as it is now (the same cell, or the same
    /// channel's cell for that time in the guide), or nil when the list no longer has its channel.
    func liveContentFocus<ID: Hashable>(
        _ focus: FocusState<ID?>.Binding, request: Binding<LiveContentFocus?>,
        memory: Binding<AnyHashable?>, match: @escaping (ID) -> ID?, onExit: @escaping () -> Void
    ) -> some View {
        modifier(LiveContentFocusModifier(focus: focus, request: request, memory: memory, match: match, onExit: onExit))
    }
}

private struct LiveContentFocusModifier<ID: Hashable>: ViewModifier {
    var focus: FocusState<ID?>.Binding
    @Binding var request: LiveContentFocus?
    /// The cell focus was last on in here. Kept outside the view (in `LiveStore`): a new
    /// category empties the list while it loads, which tears the guide or grid down.
    @Binding var memory: AnyHashable?
    let match: (ID) -> ID?
    let onExit: () -> Void

    private var last: ID? {
        get { memory as? ID }
        nonmutating set { memory = newValue }
    }
    /// Menu sent focus up to the controls, and `.enter` brings it back to `last`. Until
    /// then the list can't take focus: left to the focus engine, down from the controls
    /// picks the cell nearest them, which can be in a row laid out above the visible ones
    /// (under the info panel), and scrolling to it scrolls the remembered cell away.
    @State private var awaitingEntry = false

    func body(content: Content) -> some View {
        content
            .disabled(awaitingEntry)
            .focusSection()
            .onExitCommand {
                if let current = focus.wrappedValue { last = current }
                awaitingEntry = last.flatMap(match) != nil
                onExit()
            }
            .onChange(of: focus.wrappedValue) { _, new in
                if let new { last = new }
            }
            .onChange(of: request, initial: true) { apply() }
    }

    private func apply() {
        guard request == .enter else { return }
        request = nil
        guard awaitingEntry else { return }
        awaitingEntry = false
        guard let last, let target = match(last) else { return }
        move(to: target)
    }

    /// After a beat, and again until it takes: focus set while the controls still hold it
    /// can be dropped. Each try finds the cell again: a row scrolled into view loads its
    /// schedule, which can replace the cell it showed first.
    private func move(to id: ID) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            for _ in 0..<8 {
                let target = match(id) ?? id
                focus.wrappedValue = target
                try? await Task.sleep(for: .milliseconds(250))
                if let now = focus.wrappedValue, now == target || match(id) == now { return }
            }
        }
    }
}
