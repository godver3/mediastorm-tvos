import SwiftUI

/// The focused release down the right of the screen (`CalendarDetailPanel`): backdrop,
/// the show's name over the episode title, a metadata line, genre chips, the synopsis and
/// the cast, over a dark panel that fades in from the feed.
struct CalendarDetailPanel: View {
    let detail: CalendarItemDetail?
    let loading: Bool

    private enum Palette {
        static let surface = Color(red: 0x06 / 255, green: 0x13 / 255, blue: 0x1d / 255)
        static let border = Color(red: 0x1d / 255, green: 0x42 / 255, blue: 0x5a / 255)
        static let accent = Color(red: 0x55 / 255, green: 0xb8 / 255, blue: 1)
        static let primary = Color(red: 0xf4 / 255, green: 0xf8 / 255, blue: 0xfc / 255)
        static let secondary = Color(red: 0xa4 / 255, green: 0xb4 / 255, blue: 0xc2 / 255)
        static let chip = Color(red: 0x0d / 255, green: 0x2b / 255, blue: 0x3d / 255)
        static let chipBorder = Color(red: 0x28 / 255, green: 0x61 / 255, blue: 0x7f / 255)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let detail {
                artwork(detail)
                content(detail)
            } else {
                Text("Select a release to preview its details.")
                    .font(.system(size: 24))
                    .foregroundStyle(Palette.secondary)
                    .padding(30)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 40)
        .padding([.top, .trailing], 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            LinearGradient(stops: [.init(color: Palette.surface.opacity(0), location: 0),
                                   .init(color: Palette.surface.opacity(0.94), location: 0.12),
                                   .init(color: Palette.surface, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
                .ignoresSafeArea()
        }
        .overlay(alignment: .topTrailing) {
            if loading {
                ProgressView().tint(Palette.accent).padding(44)
                    .accessibilityLabel("Loading additional release details")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar-detail-panel")
    }

    private func artwork(_ detail: CalendarItemDetail) -> some View {
        let url = detail.backdropURL ?? detail.posterURL
        return RemoteImage(url: Artwork.url(url), size: CGSize(width: CalendarView.panelWidth - 70, height: 290)) { _ in
            Rectangle().fill(.quaternary)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .id(detail.itemKey)
    }

    private func content(_ detail: CalendarItemDetail) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                if let eyebrow = detail.eyebrow {
                    Text(eyebrow).font(.system(size: 20, weight: .bold)).tracking(0.5)
                        .foregroundStyle(Palette.accent).lineLimit(1)
                }
                Text(detail.heading).font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Palette.primary).lineLimit(2)
                    .accessibilityIdentifier("calendar-detail-title")
            }
            if !detail.metadataLine.isEmpty {
                Text(detail.metadataLine).font(.system(size: 24)).foregroundStyle(Palette.secondary).lineLimit(2)
            }
            if !detail.genreChips.isEmpty {
                CalendarFlowLayout(spacing: 10) {
                    ForEach(detail.genreChips, id: \.self) { genre in
                        Text(genre).font(.system(size: 22)).foregroundStyle(Palette.primary).lineLimit(1)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.chip))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.chipBorder, lineWidth: 1))
                    }
                }
            }
            Text(detail.synopsis).font(.system(size: 26)).foregroundStyle(Palette.primary).lineLimit(3)
            if !detail.castLine.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Rectangle().fill(Palette.border).frame(height: 1)
                    Text("Cast").font(.system(size: 24, weight: .semibold)).foregroundStyle(Palette.primary)
                    Text(detail.castLine).font(.system(size: 24)).foregroundStyle(Palette.secondary).lineLimit(2)
                }
            }
        }
        .padding(.top, 26)
        .padding(.horizontal, 4)
    }
}

/// Lays chips out in rows, wrapping at the proposed width.
struct CalendarFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let current = rows[rows.count - 1]
            rows[rows.count - 1].width += current.indices.isEmpty ? size.width : size.width + spacing
            rows[rows.count - 1].height = max(current.height, size.height)
            rows[rows.count - 1].indices.append(index)
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
