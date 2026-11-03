import SwiftUI

/// One line of text that truncates at rest and, while its focusable ancestor is focused, scrolls
/// to reveal the rest when it is wider than the row: a pause, a slow scroll to the end, a pause,
/// then back to the start, repeating. Text that fits stays still.
/// Release / file names in the source picker and the library versions list.
struct MarqueeText: View {
    let text: String

    @Environment(\.isFocused) private var isFocused
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    /// Points per second.
    private static let speed: CGFloat = 70
    private static let pause: Duration = .seconds(1.2)

    private var overflow: CGFloat { max(0, textWidth - boxWidth) }
    private var scrolling: Bool { isFocused && overflow > 1 }

    var body: some View {
        // The truncated line sizes the row; the full-width copy is laid over it only while scrolling.
        Text(text)
            .lineLimit(1)
            .opacity(scrolling ? 0 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                GeometryReader { box in
                    Color.clear.onAppear { boxWidth = box.size.width }
                        .onChange(of: box.size.width) { _, width in boxWidth = width }
                }
            }
            .overlay(alignment: .leading) {
                Text(text)
                    .lineLimit(1)
                    .fixedSize()
                    .background {
                        GeometryReader { full in
                            Color.clear.onAppear { textWidth = full.size.width }
                                .onChange(of: full.size.width) { _, width in textWidth = width }
                        }
                    }
                    .offset(x: offset)
                    .opacity(scrolling ? 1 : 0)
            }
            .clipped()
            .task(id: scrolling) {
                offset = 0
                guard scrolling else { return }
                let distance = overflow
                let duration = Double(distance / Self.speed)
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.pause)
                    guard !Task.isCancelled else { return }
                    withAnimation(.linear(duration: duration)) { offset = -distance }
                    try? await Task.sleep(for: .seconds(duration) + Self.pause)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.4)) { offset = 0 }
                    try? await Task.sleep(for: .seconds(0.4))
                }
            }
    }
}
