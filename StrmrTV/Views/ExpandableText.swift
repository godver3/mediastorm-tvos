import SwiftUI

/// A block of text cut to `lineLimit` lines that focus can land on. When the text is cut
/// off, selecting it calls `expand`, for the page to show it whole (`FullTextOverlay`).
struct ExpandableText: View {
    let text: String
    var lineLimit = 7
    var fontSize: CGFloat = 24
    /// Focusable only when cut off (a details overview); otherwise always, so the page can
    /// open on it (a biography).
    var onlyWhenTruncated = false
    let expand: () -> Void

    @State private var shownHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private var isTruncated: Bool { fullHeight > shownHeight + 1 }

    var body: some View {
        Button {
            if isTruncated { expand() }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text(text)
                    .font(.system(size: fontSize))
                    .lineLimit(lineLimit)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
                    // The same text uncut, unseen, to tell whether the shown one is cut off.
                    .background(alignment: .topLeading) {
                        Text(text)
                            .font(.system(size: fontSize))
                            .fixedSize(horizontal: false, vertical: true)
                            .hidden()
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                    }
                if isTruncated {
                    Text("More").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(TextBlockStyle())
        .disabled(onlyWhenTruncated && !isTruncated)
    }
}

/// A soft platter behind the focused text block, rather than the system's white card.
private struct TextBlockStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isFocused ? 0.14 : 0)))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.15), value: isFocused)
            // Out past the text, but not over the line above it.
            .padding(.horizontal, -16)
            .padding(.vertical, -8)
    }
}

/// The whole text over the page, which the page blurs behind it; up and down scroll
/// it, Menu closes it.
struct FullTextOverlay: View {
    let title: String?
    let text: String
    var fontSize: CGFloat = 28
    let close: () -> Void

    @State private var position = ScrollPosition(y: 0)
    @State private var offset: CGFloat = 0
    @State private var maxOffset: CGFloat = 0
    @FocusState private var focused: Bool

    /// How far one press of up or down scrolls.
    private static let step: CGFloat = 300

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    if let title { Text(title).font(.system(size: 48, weight: .bold)) }
                    Text(text).font(.system(size: fontSize)).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 1300, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 80)
            }
            .scrollPosition($position)
            .scrollDisabled(true)
            .onScrollGeometryChange(for: CGFloat.self, of: { max(0, $0.contentSize.height - $0.containerSize.height) }) {
                _, new in maxOffset = new
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onMoveCommand(perform: move)
            .onExitCommand(perform: close)
        }
        .onAppear { focused = true }
    }

    private func move(_ direction: MoveCommandDirection) {
        let next: CGFloat = switch direction {
        case .down: offset + Self.step
        case .up: offset - Self.step
        default: offset
        }
        offset = min(max(next, 0), maxOffset)
        withAnimation(.easeOut(duration: 0.25)) { position.scrollTo(y: offset) }
    }
}
