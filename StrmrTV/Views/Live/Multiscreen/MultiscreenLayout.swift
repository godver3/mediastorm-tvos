import CoreGraphics

enum MultiscreenDirection {
    case left, right, up, down
}

/// Where the screens go (the Expo app's `multiscreenFrames` / `multiscreenNeighbor`). Frames
/// are keyed by slot index, not by display order, so a slot keeps its identity as the layout
/// changes around it.
enum MultiscreenLayout {
    /// Equal 16:9 tiles in a centred grid of ceil(sqrt(n)) columns; or, with `expanded`, that
    /// tile at 72% of the width and the others in a column beside it (two tiles: side by side).
    /// One tile fills `size`.
    static func frames(_ ids: [Int], expanded: Int?, size: CGSize, gap: CGFloat) -> [Int: CGRect] {
        guard let first = ids.first else { return [:] }
        if ids.count == 1 { return [first: CGRect(origin: .zero, size: size)] }
        guard let expanded, ids.contains(expanded) else {
            return grid(ids, in: CGRect(origin: .zero, size: size), columns: Int(Double(ids.count).squareRoot().rounded(.up)),
                        gap: gap)
        }
        let width = size.width, height = size.height
        let largeWidth = min((width - gap) * 0.72, height * 16 / 9)
        let smallWidth = min((width - gap) * 0.28, largeWidth * 0.28 / 0.72)
        let left = max(0, (width - largeWidth - smallWidth - gap) / 2)
        let largeHeight = largeWidth * 9 / 16
        var frames: [Int: CGRect] = [:]
        if ids.count == 2 {
            let smallHeight = smallWidth * 9 / 16
            for (i, id) in ids.enumerated() {
                let isLarge = id == expanded
                let x = left + (i == 0 ? 0 : (expanded == ids[0] ? largeWidth : smallWidth) + gap)
                let h = isLarge ? largeHeight : smallHeight
                frames[id] = CGRect(x: x, y: (height - h) / 2, width: isLarge ? largeWidth : smallWidth, height: h)
            }
            return frames
        }
        frames[expanded] = CGRect(x: left, y: (height - largeHeight) / 2, width: largeWidth, height: largeHeight)
        let others = ids.filter { $0 != expanded }
        let columns = max(1, Int((Double(others.count) / 3).squareRoot().rounded(.up)))
        let column = CGRect(x: left + largeWidth + gap, y: 0, width: smallWidth, height: height)
        return frames.merging(grid(others, in: column, columns: columns, gap: gap)) { $1 }
    }

    private static func grid(_ ids: [Int], in bounds: CGRect, columns: Int, gap: CGFloat) -> [Int: CGRect] {
        let cols = CGFloat(columns)
        let rows = CGFloat((ids.count + columns - 1) / columns)
        // Keeps the geometry valid however many tiles there are.
        let spacing = min(gap, bounds.width / (cols * 4), bounds.height / (rows * 4))
        let w = min((bounds.width - spacing * (cols - 1)) / cols, (bounds.height - spacing * (rows - 1)) / rows * 16 / 9)
        let h = w * 9 / 16
        let left = bounds.minX + max(0, (bounds.width - w * cols - spacing * (cols - 1)) / 2)
        let top = bounds.minY + max(0, (bounds.height - h * rows - spacing * (rows - 1)) / 2)
        var frames: [Int: CGRect] = [:]
        for (i, id) in ids.enumerated() {
            frames[id] = CGRect(x: left + CGFloat(i % columns) * (w + spacing),
                                y: top + CGFloat(i / columns) * (h + spacing), width: w, height: h)
        }
        return frames
    }

    /// The tile `direction` leads to from `selected`: the nearest by the distance between facing
    /// edges (a large tile spans several small ones) plus twice the offset of their centres
    /// across that direction. Ties go to the lower slot. Nil when nothing lies that way.
    static func neighbor(_ frames: [Int: CGRect], of selected: Int, _ direction: MultiscreenDirection) -> Int? {
        guard let a = frames[selected] else { return nil }
        var best: (id: Int, score: CGFloat)?
        for (id, b) in frames where id != selected {
            let distance: CGFloat
            let cross: CGFloat
            switch direction {
            case .right: distance = b.minX - a.maxX
            case .left: distance = a.minX - b.maxX
            case .down: distance = b.minY - a.maxY
            case .up: distance = a.minY - b.maxY
            }
            guard distance >= -0.01 else { continue }
            switch direction {
            case .left, .right: cross = abs(b.midY - a.midY)
            case .up, .down: cross = abs(b.midX - a.midX)
            }
            let score = distance + cross * 2
            if best == nil || score < best!.score || (score == best!.score && id < best!.id) {
                best = (id, score)
            }
        }
        return best?.id
    }
}
