import UIKit

// Tweaks to AVKit's stock tvOS transport bar.

@MainActor
enum NativeChrome {}

/// Keeps AVKit's stock Audio and / or Subtitles buttons hidden while a player is on screen.
///
/// AetherEngine serves AVPlayer only the active audio track, so AVKit's own Audio
/// button would list a single language, and subtitles are drawn by the app's overlay
/// rather than AVKit's legible group; the player shows custom menus with every track
/// instead. There is no public API to drop a built-in transport-bar item, so the
/// buttons are matched by accessibility identifier. AVKit recycles these cells (a
/// hidden cell can come back as a custom menu's button), so every pass re-derives
/// visibility from the identifier, and the remaining buttons are moved right into the
/// trailing slots so they stay right-aligned instead of leaving holes, with AVKit's
/// Audio button (when shown) leading so the order is always audio, subtitles, settings.
///
/// The buttons are moved from inside the row's own `layoutSubviews` (see
/// `UICollectionView.installLayoutHook`), so AVKit's layout and the move land in the same
/// pass and no frame is drawn with the buttons back in AVKit's slots. A run-loop pass
/// finds the row and catches cell recycling that happens without a layout.
@MainActor
final class TransportSettingsHider {
    static let audible = "AVAudibleSettings"
    static let legible = "AVLegibleSettings"

    private var hidden: Set<String> = []

    private weak var root: UIView?
    private weak var collection: UICollectionView?
    private var observer: CFRunLoopObserver?
    private var lastSearch: CFTimeInterval = 0

    /// The hider whose row the layout hook adjusts.
    fileprivate static weak var active: TransportSettingsHider?

    func start(on root: UIView, hiding identifiers: Set<String>) {
        self.root = root
        hidden = identifiers
        UICollectionView.installLayoutHook()
        Self.active = self
        if observer == nil {
            // Order just below Core Animation's commit observer (2_000_000).
            let observer = CFRunLoopObserverCreateWithHandler(
                kCFAllocatorDefault, CFRunLoopActivity.beforeWaiting.rawValue, true, 1_999_999
            ) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            self.observer = observer
        }
        apply()
    }

    /// Stops hiding and puts AVKit's button and the row back as they were.
    func stop() {
        if let observer {
            CFRunLoopObserverInvalidate(observer)
            self.observer = nil
        }
        if Self.active === self { Self.active = nil }
        guard let collection else { return }
        for cell in collection.visibleCells {
            cell.isHidden = false
            if let path = collection.indexPath(for: cell),
               let frame = collection.collectionViewLayout.layoutAttributesForItem(at: path)?.frame {
                cell.center = CGPoint(x: frame.midX, y: frame.midY)
            }
        }
    }

    private func tick() {
        guard let root, root.window != nil else { return }
        apply()
    }

    /// Called after any collection view lays out; only the transport bar's row matters.
    fileprivate func didLayout(_ view: UICollectionView) {
        if view === collection { apply() }
    }

    func apply() {
        if collection == nil || collection?.window == nil, let root {
            // The tree walk is the only costly part; cap it while the bar is absent.
            let now = CACurrentMediaTime()
            guard now - lastSearch > 0.05 else { return }
            lastSearch = now
            collection = Self.findToolCollection(in: root)
        }
        guard let collection else { return }
        let cells = collection.visibleCells
        let layout = collection.collectionViewLayout
        // AVKit's own slot for each cell; the cells are moved off these, so always
        // start from the layout rather than from the cells' current frames.
        let slots: [(cell: UICollectionViewCell, frame: CGRect)] = cells.compactMap { cell in
            guard let path = collection.indexPath(for: cell),
                  let frame = layout.layoutAttributesForItem(at: path)?.frame else { return nil }
            return (cell, frame)
        }
        for (cell, _) in slots {
            let hide = cell.accessibilityIdentifier.map(hidden.contains) ?? false
            if cell.isHidden != hide { cell.isHidden = hide }
        }
        // Close the holes the hidden buttons leave (they sit at the trailing end) by moving
        // the remaining buttons, in order, into the trailing slots. The cells are moved rather
        // than the collection: a transform on the collection showed up late on screen while
        // the bar faded in, so the Subtitles button jumped.
        let ordered = slots.sorted { $0.frame.minX < $1.frame.minX }
        // AVKit puts its own Audio button after the custom menus; the bar always reads
        // audio, subtitles, settings, so it leads instead.
        let visible = ordered.filter { !$0.cell.isHidden }
        let isAudio = { (slot: (cell: UICollectionViewCell, frame: CGRect)) in slot.cell.accessibilityIdentifier == Self.audible }
        let shown = visible.filter(isAudio) + visible.filter { !isAudio($0) }
        let targets = ordered.suffix(shown.count).map(\.frame)
        for (slot, frame) in zip(shown, targets) {
            // `center`, not `frame`: a focused cell may carry a transform.
            let target = CGPoint(x: frame.midX, y: slot.frame.midY)
            if slot.cell.center != target { slot.cell.center = target }
        }
        if collection.transform != .identity { collection.transform = .identity }
    }

    /// The collection view hosting the transport bar's round tool buttons.
    private static func findToolCollection(in view: UIView) -> UICollectionView? {
        if let cv = view as? UICollectionView,
           cv.visibleCells.contains(where: { $0.accessibilityIdentifier == legible || $0.accessibilityIdentifier == audible }) {
            return cv
        }
        for sub in view.subviews {
            if let found = findToolCollection(in: sub) { return found }
        }
        return nil
    }
}

extension UICollectionView {
    private static var layoutHookInstalled = false

    /// Swizzles `layoutSubviews` so `TransportSettingsHider` can move the transport bar's
    /// buttons in the same pass that AVKit lays them out. Other collection views pay
    /// only an identity check.
    static func installLayoutHook() {
        guard !layoutHookInstalled else { return }
        layoutHookInstalled = true
        let original = #selector(UICollectionView.layoutSubviews)
        let swizzled = #selector(UICollectionView.strmr_layoutSubviews)
        guard let swizzledMethod = class_getInstanceMethod(self, swizzled),
              let originalMethod = class_getInstanceMethod(self, original) else { return }
        // Add first so an inherited implementation is never exchanged for every UIView.
        if class_addMethod(self, original, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod)) {
            class_replaceMethod(self, swizzled, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod))
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }

    @objc private func strmr_layoutSubviews() {
        strmr_layoutSubviews() // the original implementation, after the swap
        MainActor.assumeIsolated { TransportSettingsHider.active?.didLayout(self) }
    }
}

/// One row of the audio or subtitle menu.
struct TrackMenuItem: Equatable {
    let id: Int
    let title: String
    let detail: String?
    let isSelected: Bool
}

extension NativeChrome {
    /// One track row, on one line: "English · SDH · SRT". AVKit's menu lays out two-line rows (a
    /// `subtitle`) wrongly under fast focus moves: holding Down through a long list left rows
    /// overlapping and blank gaps where rows should be, and they stayed after the scroll settled.
    /// One-line rows don't (checked with the chrome probe), so the detail joins
    /// the title, cut to the row's width (a wrapped line would make it two lines again).
    private static func trackAction(_ item: TrackMenuItem, onPick: @escaping @MainActor () -> Void) -> UIAction {
        return UIAction(title: rowTitle(item), state: item.isSelected ? .on : .off) { _ in
            if !item.isSelected { onPick() }
        }
    }

    /// "Title · detail" on one line. When it is too long the middle of the detail (a track's own
    /// name) is cut, so the title and the detail's last part (the format) stay readable:
    /// "English · Forced · Sign… · ASS".
    static func rowTitle(_ item: TrackMenuItem) -> String {
        let parts = (item.detail ?? "").components(separatedBy: " · ").filter { !$0.isEmpty }
        let full = ([item.title] + parts).joined(separator: " · ")
        guard width(full, rowFont) > rowBudget, parts.count > 1, let format = parts.last else {
            return fitted(full, budget: rowBudget, font: rowFont)
        }
        let ends = width("\(item.title) ·  · \(format)", rowFont)
        let middle = fitted(parts.dropLast().joined(separator: " · "), budget: rowBudget - ends, font: rowFont)
        return fitted("\(item.title) · \(middle) · \(format)", budget: rowBudget, font: rowFont)
    }

    // A line seen to fit a menu row, measured in a stand-in font: the menu's own font is
    // private, but the same face at any size keeps the ratio.
    private static let rowFont = UIFont.preferredFont(forTextStyle: .body)
    private static let rowBudget = width("Signs & Songs [Group]", rowFont)

    private static func width(_ text: String, _ font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// `text`, or as much of it as fits `budget` followed by "…".
    static func fitted(_ text: String, budget: CGFloat, font: UIFont) -> String {
        let line = text.replacingOccurrences(of: "\n", with: " ")
        guard width(line, font) > budget else { return line }
        var cut = Substring(line)
        while !cut.isEmpty, width(cut.trimmingCharacters(in: .whitespaces) + "…", font) > budget {
            cut = cut.dropLast()
        }
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Mirrors the stock tvOS Audio menu: a waveform button whose popover has an
    /// inline "Audio Track" section with a checkmark on the active track.
    static func audioMenu(_ items: [TrackMenuItem], onSelect: @escaping @MainActor (Int) -> Void) -> UIMenu {
        let actions = items.map { item in
            trackAction(item) { onSelect(item.id) }
        }
        let tracks = UIMenu(title: "Audio Track", options: [.displayInline, .singleSelection], children: actions)
        return UIMenu(title: "Audio", image: UIImage(systemName: "waveform"), children: [tracks])
    }

    /// Mirrors the stock tvOS Subtitles menu: a captions button whose popover has an inline
    /// "Subtitles" section with Off first and a checkmark on the active track, then (with
    /// `onSearch` / `onTranslate`) Search Online… and Translate…, then a "Style" submenu of quick size / background / position
    /// picks for the device's subtitle style.
    static func subtitleMenu(_ items: [TrackMenuItem], offSelected: Bool, style: SubtitleStyle,
                             onSelect: @escaping @MainActor (Int?) -> Void,
                             onStyle: @escaping @MainActor (SubtitleStyle) -> Void,
                             onSearch: (@MainActor () -> Void)? = nil,
                             onTranslate: (@MainActor () -> Void)? = nil) -> UIMenu {
        let off = UIAction(title: String(localized: "Off"), state: offSelected ? .on : .off) { _ in
            if !offSelected { onSelect(nil) }
        }
        let actions = items.map { item in
            trackAction(item) { onSelect(item.id) }
        }
        let tracks = UIMenu(title: String(localized: "Subtitles"), options: [.displayInline, .singleSelection],
                            children: [off] + actions)
        var children: [UIMenuElement] = [tracks]
        var online: [UIAction] = []
        if let onSearch {
            online.append(UIAction(title: String(localized: "Search Online…"),
                                   image: UIImage(systemName: "magnifyingglass")) { _ in onSearch() })
        }
        if let onTranslate {
            online.append(UIAction(title: String(localized: "Translate…"),
                                   image: UIImage(systemName: "character.bubble")) { _ in onTranslate() })
        }
        if !online.isEmpty { children.append(UIMenu(title: "", options: .displayInline, children: online)) }
        children.append(styleMenu(style, onStyle: onStyle))
        return UIMenu(title: String(localized: "Subtitles"), image: UIImage(systemName: "captions.bubble"),
                      children: children)
    }

    /// Quick picks over the device's `SubtitleStyle`; the full set lives in Settings.
    static func styleMenu(_ style: SubtitleStyle, onStyle: @escaping @MainActor (SubtitleStyle) -> Void) -> UIMenu {
        func section<V: Equatable>(_ title: String, _ values: [V], _ keyPath: WritableKeyPath<SubtitleStyle, V>,
                                   name: (V) -> String) -> UIMenu {
            let actions = values.map { value in
                UIAction(title: name(value), state: style[keyPath: keyPath] == value ? .on : .off) { _ in
                    var next = style
                    next[keyPath: keyPath] = value
                    if next != style { onStyle(next) }
                }
            }
            return UIMenu(title: title, options: [.displayInline, .singleSelection], children: actions)
        }
        let menu = UIMenu(title: String(localized: "Style"), image: UIImage(systemName: "textformat.size"), children: [
            section(String(localized: "Size"), SubtitleStyle.sizes, \.size, name: SubtitleStyle.sizeName),
            section(String(localized: "Background"), SubtitleStyle.backgroundOpacities, \.backgroundOpacity,
                    name: SubtitleStyle.percent),
            section(String(localized: "Position"), SubtitleStyle.margins, \.bottomMargin, name: SubtitleStyle.marginName),
        ])
        menu.subtitle = SubtitleStyle.sizeName(style.size)
        return menu
    }

    /// A gear button for playback settings, beside Audio and Subtitles. Its popover has an
    /// inline "Playback Speed" section with a checkmark on the current speed, then `extra`
    /// (Switch Source).
    static func settingsMenu(speeds: [Float], current: Float, extra: [UIMenuElement] = [],
                             onSelectSpeed: @escaping @MainActor (Float) -> Void) -> UIMenu {
        let actions = speeds.map { speed in
            UIAction(title: speedTitle(speed), state: speed == current ? .on : .off) { _ in
                if speed != current { onSelectSpeed(speed) }
            }
        }
        let speedSection = UIMenu(title: String(localized: "Playback Speed"),
                                  options: [.displayInline, .singleSelection], children: actions)
        return UIMenu(title: String(localized: "Settings"), image: UIImage(systemName: "gearshape"),
                      children: [speedSection] + (extra.isEmpty ? [] : [UIMenu(title: "", options: .displayInline, children: extra)]))
    }

    /// "Normal" for 1x, otherwise "1.25×" style.
    static func speedTitle(_ speed: Float) -> String {
        if speed == 1 { return String(localized: "Normal") }
        let number = speed.formatted(.number.precision(.fractionLength(0...2)))
        return "\(number)×"
    }
}
