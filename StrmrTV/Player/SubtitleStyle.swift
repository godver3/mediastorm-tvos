import Combine
import SwiftUI
import UIKit

/// How text subtitles are drawn on this device: the server's style (the Expo app's
/// `playback.subtitle*` settings) with any setting this device overrides.
struct SubtitleStyle: Codable, Equatable {
    enum Edge: String, Codable, CaseIterable {
        case none, shadow, outline
    }

    /// Scale of the base text size (62 pt at 1.0, the Expo app's tvOS baseline, so a seeded
    /// `subtitleSize` looks the same); bitmap cues scale by it too.
    var size: Double = 1.0
    /// Text colour as `#RRGGBB`.
    var textColor: String = "#FFFFFF"
    var textOpacity: Double = 1.0
    var bold: Bool = true
    var edge: Edge = .shadow
    var outlineColor: String = "#000000"
    /// 0...1, as the backend's `subtitleOutlineWeight`.
    var outlineWeight: Double = 0.35
    /// Box behind the text; 0 = no box.
    var backgroundOpacity: Double = 0
    var backgroundColor: String = "#000000"
    /// Distance of the text's baseline block from the bottom of the video, in points (1080p).
    var bottomMargin: Double = 110

    static let `default` = SubtitleStyle()
    static let baseFontSize: CGFloat = 62

    // Choices offered in Settings and the player's quick menu.
    static let sizes: [Double] = [0.6, 0.8, 1.0, 1.25, 1.5, 2.0]
    static let opacities: [Double] = [1.0, 0.75, 0.5]
    static let backgroundOpacities: [Double] = [0, 0.25, 0.5, 0.75, 1.0]
    static let outlineWeights: [Double] = [0.2, 0.35, 0.6]
    static let margins: [Double] = [60, 110, 200, 320]
    static let palette: [(name: String, hex: String)] = [
        (String(localized: "White"), "#FFFFFF"), (String(localized: "Yellow"), "#FFFF00"),
        (String(localized: "Cyan"), "#00FFFF"), (String(localized: "Green"), "#00FF00"),
        (String(localized: "Magenta"), "#FF00FF"), (String(localized: "Red"), "#FF0000"),
        (String(localized: "Blue"), "#0000FF"), (String(localized: "Grey"), "#808080"),
        (String(localized: "Black"), "#000000"),
    ]

    static func sizeName(_ size: Double) -> String {
        switch size {
        case ..<0.7: String(localized: "Extra Small")
        case ..<0.9: String(localized: "Small")
        case ..<1.1: String(localized: "Medium")
        case ..<1.35: String(localized: "Large")
        case ..<1.75: String(localized: "Extra Large")
        default: String(localized: "Huge")
        }
    }

    static func marginName(_ margin: Double) -> String {
        switch margin {
        case ..<80: String(localized: "Bottom")
        case ..<150: String(localized: "Default")
        case ..<250: String(localized: "Raised")
        default: String(localized: "High")
        }
    }

    static func weightName(_ weight: Double) -> String {
        switch weight {
        case ..<0.3: String(localized: "Thin")
        case ..<0.5: String(localized: "Medium")
        default: String(localized: "Thick")
        }
    }

    static func colorName(_ hex: String) -> String {
        palette.first { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }?.name ?? hex.uppercased()
    }

    static func percent(_ value: Double) -> String {
        value <= 0 ? String(localized: "Off") : "\(Int((value * 100).rounded()))%"
    }

    // MARK: Rendering values

    var font: UIFont {
        .systemFont(ofSize: Self.baseFontSize * size, weight: bold ? .semibold : .regular)
    }

    var foreground: UIColor { UIColor(hex: textColor).withAlphaComponent(textOpacity) }
    var boxColor: UIColor { UIColor(hex: backgroundColor).withAlphaComponent(backgroundOpacity) }

    /// `NSAttributedString.Key.strokeWidth` for the outline: negative strokes and fills.
    var strokeWidth: CGFloat { -(2 + 8 * outlineWeight) }

    func attributed(_ text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: foreground, .paragraphStyle: paragraph,
        ]
        if edge == .outline {
            attributes[.strokeColor] = UIColor(hex: outlineColor).withAlphaComponent(textOpacity)
            attributes[.strokeWidth] = strokeWidth
        }
        return NSAttributedString(string: text, attributes: attributes)
    }
}

extension SubtitleStyle {
    /// The backend's `playback.subtitle*` fields (Expo app settings), filled in by the server.
    struct Server: Decodable {
        let subtitleSize: Double?
        let subtitleColor: String?
        let subtitleOpacity: Double?
        let subtitleBold: Bool?
        let subtitleOutlineEnabled: Bool?
        let subtitleOutlineColor: String?
        let subtitleOutlineWeight: Double?
        let subtitleBackgroundEnabled: Bool?
        let subtitleBackgroundColor: String?
        let subtitleBackgroundOpacity: Double?

        /// Whether the server sent any style at all (older servers send none).
        var isEmpty: Bool {
            subtitleSize == nil && subtitleColor == nil && subtitleBackgroundEnabled == nil
                && subtitleOutlineEnabled == nil
        }

        /// `self` with `fallback` filling every field it leaves out (device override over profile).
        func merged(over fallback: Server?) -> Server {
            guard let fallback else { return self }
            return Server(
                subtitleSize: subtitleSize ?? fallback.subtitleSize,
                subtitleColor: subtitleColor ?? fallback.subtitleColor,
                subtitleOpacity: subtitleOpacity ?? fallback.subtitleOpacity,
                subtitleBold: subtitleBold ?? fallback.subtitleBold,
                subtitleOutlineEnabled: subtitleOutlineEnabled ?? fallback.subtitleOutlineEnabled,
                subtitleOutlineColor: subtitleOutlineColor ?? fallback.subtitleOutlineColor,
                subtitleOutlineWeight: subtitleOutlineWeight ?? fallback.subtitleOutlineWeight,
                subtitleBackgroundEnabled: subtitleBackgroundEnabled ?? fallback.subtitleBackgroundEnabled,
                subtitleBackgroundColor: subtitleBackgroundColor ?? fallback.subtitleBackgroundColor,
                subtitleBackgroundOpacity: subtitleBackgroundOpacity ?? fallback.subtitleBackgroundOpacity)
        }
    }

    /// The device style seeded from the server's: the outline / box map directly; with neither
    /// outline nor box the text keeps a drop shadow so it stays legible.
    init(server s: Server) {
        self.init()
        if let v = s.subtitleSize, v > 0 { size = min(max(v, 0.5), 2.5) }
        if let v = s.subtitleColor, UIColor.isHex(v) { textColor = v.uppercased() }
        if let v = s.subtitleOpacity, v > 0 { textOpacity = min(v, 1) }
        if let v = s.subtitleBold { bold = v }
        edge = s.subtitleOutlineEnabled == true ? .outline : .shadow
        if let v = s.subtitleOutlineColor, UIColor.isHex(v) { outlineColor = v.uppercased() }
        if let v = s.subtitleOutlineWeight, v > 0 { outlineWeight = min(v, 1) }
        if s.subtitleBackgroundEnabled == true {
            backgroundOpacity = min(max(s.subtitleBackgroundOpacity ?? 0.6, 0), 1)
        }
        if let v = s.subtitleBackgroundColor, UIColor.isHex(v) { backgroundColor = v.uppercased() }
    }
}

extension SubtitleStyle {
    /// The settings this device sets for itself; nil follows the server's.
    struct Overrides: Codable, Equatable {
        var size: Double?
        var textColor: String?
        var textOpacity: Double?
        var bold: Bool?
        var edge: Edge?
        var outlineColor: String?
        var outlineWeight: Double?
        var backgroundOpacity: Double?
        var backgroundColor: String?
        var bottomMargin: Double?

        var isEmpty: Bool { self == Overrides() }

        func applied(to base: SubtitleStyle) -> SubtitleStyle {
            var s = base
            if let size { s.size = size }
            if let textColor { s.textColor = textColor }
            if let textOpacity { s.textOpacity = textOpacity }
            if let bold { s.bold = bold }
            if let edge { s.edge = edge }
            if let outlineColor { s.outlineColor = outlineColor }
            if let outlineWeight { s.outlineWeight = outlineWeight }
            if let backgroundOpacity { s.backgroundOpacity = backgroundOpacity }
            if let backgroundColor { s.backgroundColor = backgroundColor }
            if let bottomMargin { s.bottomMargin = bottomMargin }
            return s
        }

        /// Overrides for each setting `new` changes from `old` (the player's quick menu
        /// hands back a whole style).
        mutating func record(from old: SubtitleStyle, to new: SubtitleStyle) {
            if new.size != old.size { size = new.size }
            if new.textColor != old.textColor { textColor = new.textColor }
            if new.textOpacity != old.textOpacity { textOpacity = new.textOpacity }
            if new.bold != old.bold { bold = new.bold }
            if new.edge != old.edge { edge = new.edge }
            if new.outlineColor != old.outlineColor { outlineColor = new.outlineColor }
            if new.outlineWeight != old.outlineWeight { outlineWeight = new.outlineWeight }
            if new.backgroundOpacity != old.backgroundOpacity { backgroundOpacity = new.backgroundOpacity }
            if new.backgroundColor != old.backgroundColor { backgroundColor = new.backgroundColor }
            if new.bottomMargin != old.bottomMargin { bottomMargin = new.bottomMargin }
        }
    }
}

/// The device's subtitle style: the server's (this device's client settings, then the
/// profile's `playback.subtitle*`), with each setting this device overrides on top.
/// Settings and the player's quick menu write it; the overlay follows `$style` live.
@MainActor
final class SubtitleStyleStore: ObservableObject {
    static let shared = SubtitleStyleStore()

    private static let overridesKey = "subtitle.style.overrides"
    private static let serverKey = "subtitle.style.server"
    /// A whole style saved by earlier builds (copied from the server once, then edited);
    /// turned into overrides once the server's style is known.
    private static let legacyKey = "subtitle.style.v1"
    private static let legacyKeys = [legacyKey, "subtitle.style.seeded", "subtitle.style.custom"]
    private let defaults = UserDefaults.standard

    /// The server's style as last read; the app's default before that or from servers
    /// that send none.
    @Published private(set) var server: SubtitleStyle
    @Published private(set) var overrides: SubtitleStyle.Overrides {
        didSet {
            if let data = try? JSONEncoder().encode(overrides) { defaults.set(data, forKey: Self.overridesKey) }
        }
    }
    private var legacy: SubtitleStyle?
    /// Set while `style` is recomputed, so it isn't taken for an edit.
    private var resolving = false

    /// The style drawn. Setting it overrides each setting it changes.
    @Published var style: SubtitleStyle {
        didSet {
            guard !resolving, style != oldValue else { return }
            // Before the server's style is known, an edit changes the old saved style.
            if legacy != nil { legacy = style } else { overrides.record(from: oldValue, to: style) }
        }
    }

    private init() {
        let decoder = JSONDecoder()
        let server = defaults.data(forKey: Self.serverKey).flatMap { try? decoder.decode(SubtitleStyle.self, from: $0) }
            ?? .default
        let overrides = defaults.data(forKey: Self.overridesKey)
            .flatMap { try? decoder.decode(SubtitleStyle.Overrides.self, from: $0) } ?? .init()
        legacy = defaults.data(forKey: Self.legacyKey).flatMap { try? decoder.decode(SubtitleStyle.self, from: $0) }
        _server = Published(initialValue: server)
        _overrides = Published(initialValue: overrides)
        _style = Published(initialValue: legacy ?? overrides.applied(to: server))
    }

    /// Takes the server's style; settings this device doesn't override follow it.
    func adopt(_ value: SubtitleStyle.Server?) {
        guard let value, !value.isEmpty else { return }
        let next = SubtitleStyle(server: value)
        if let legacy {
            // The settings the old saved style set differently from the server's.
            var migrated = SubtitleStyle.Overrides()
            migrated.record(from: next, to: legacy)
            overrides = migrated
            self.legacy = nil
            Self.legacyKeys.forEach(defaults.removeObject(forKey:))
        }
        if next != server {
            server = next
            if let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: Self.serverKey) }
        }
        resolve()
    }

    /// A setting's override, for Settings; nil follows the server.
    func binding<Value>(_ path: WritableKeyPath<SubtitleStyle.Overrides, Value?>) -> Binding<Value?> {
        Binding(get: { self.overrides[keyPath: path] }, set: {
            self.overrides[keyPath: path] = $0
            self.resolve()
        })
    }

    /// Every setting follows the server again.
    func reset() {
        overrides = .init()
        resolve()
    }

    private func resolve() {
        guard legacy == nil else { return }
        let next = overrides.applied(to: server)
        guard next != style else { return }
        resolving = true
        style = next
        resolving = false
    }
}

extension UIColor {
    static func isHex(_ hex: String) -> Bool {
        let s = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        return s.count == 6 && UInt32(s, radix: 16) != nil
    }

    /// `#RRGGBB`; white when malformed.
    convenience init(hex: String) {
        let s = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            self.init(white: 1, alpha: 1)
            return
        }
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
