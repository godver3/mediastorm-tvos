import AetherEngine
import UIKit

/// Draws the engine's overlay cues (`subtitleCues` against `clock.sourceTime`) on the
/// software route, where there is no AVPlayer and so no native legible rendition, and for
/// bitmap (PGS / DVB / DVD) tracks on the native route. Text follows the device's
/// `SubtitleStyle`; bitmap cues scale by its size.
final class SubtitleOverlayView: UIView {
    private let textView = SubtitleTextView()
    private let imageView = UIImageView()
    private var bottomConstraint: NSLayoutConstraint!
    private var sideConstraints: [NSLayoutConstraint] = []
    /// The style is in 1080p points (the TV's screen). A phone or tablet lays it out on the 16:9
    /// frame that fits the view, at that frame's height over 1080 (`SubtitleOverlayView+Phone`), so
    /// a size reads the same share of the picture on every screen, in either orientation.
    private var layoutScale: CGFloat = 1
    /// The text's scale: on a phone the screen's short side over 1080, so a size reads the same
    /// in portrait as in landscape (as the Expo app's fixed sizes did) rather than shrinking to
    /// the portrait video band; margins still follow the picture's frame. 1 on a TV.
    private var textScale: CGFloat = 1
    /// How far that frame sits inside the view on each side; zero on a TV.
    private var canvasInsets: UIEdgeInsets = .zero
    private var cues: [SubtitleCue] = []
    private var shownID: Int?
    private var shownImage: SubtitleImage?
    private var lastSourceTime: Double = 0

    #if os(iOS)
    /// The source's coded size and pixel aspect (from the engine), so bitmap cues land on the
    /// picture; zero until known, when a 16:9 picture is assumed.
    var videoSize: CGSize = .zero {
        didSet { if videoSize != oldValue { setNeedsLayout() } }
    }
    var pixelAspect: CGFloat = 1 {
        didSet { if pixelAspect != oldValue { setNeedsLayout() } }
    }
    #endif

    var style: SubtitleStyle = .default {
        didSet {
            guard style != oldValue else { return }
            applyStyle()
            if let shownImage { imageView.frame = frame(for: shownImage) }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false

        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)

        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)

        bottomConstraint = textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -style.bottomMargin)
        sideConstraints = [
            textView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 160),
            textView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -160),
        ]
        NSLayoutConstraint.activate(sideConstraints + [
            textView.centerXAnchor.constraint(equalTo: centerXAnchor),
            bottomConstraint,
        ])
    }

    private func applyStyle() {
        textView.style = style
        textView.scale = textScale
        bottomConstraint.constant = -(canvasInsets.bottom + style.bottomMargin * layoutScale)
        sideConstraints.first?.constant = canvasInsets.left + 160 * layoutScale
        sideConstraints.last?.constant = -(canvasInsets.right + 160 * layoutScale)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        #if os(iOS)
        let canvas = Self.canvas(in: bounds)
        let scale = canvas.height > 0 ? min(1, canvas.height / 1080) : 1
        let insets = UIEdgeInsets(top: canvas.minY - bounds.minY, left: canvas.minX - bounds.minX,
                                  bottom: bounds.maxY - canvas.maxY, right: bounds.maxX - canvas.maxX)
        let text = min(1, min(bounds.width, bounds.height) / 1080)
        if abs(scale - layoutScale) > 0.001 || abs(text - textScale) > 0.001 || insets != canvasInsets {
            layoutScale = scale
            textScale = text
            canvasInsets = insets
            applyStyle()
        }
        #endif
        if let shownImage { imageView.frame = frame(for: shownImage) }
    }

    func setCues(_ cues: [SubtitleCue]) {
        self.cues = cues
        // Re-evaluate against the new list right away: the engine republishes it whole as cues
        // arrive or an open-ended one gets its end, so the cue on screen is kept (no blank frame)
        // unless the new list no longer shows it, and a removed cue does not linger.
        update(sourceTime: lastSourceTime)
    }

    func update(sourceTime: Double) {
        lastSourceTime = sourceTime
        let active = cues.last { $0.startTime <= sourceTime && sourceTime < $0.endTime }
        guard active?.id != shownID else { return }
        shownID = active?.id
        textView.text = nil
        imageView.image = nil
        shownImage = nil
        guard let active else { return }
        switch active.body {
        case .text, .richText:
            textView.text = active.text
        case let .image(image):
            shownImage = image
            imageView.image = UIImage(cgImage: image.cgImage)
            imageView.frame = frame(for: image)
        }
    }

    /// Shows fixed text instead of cues (the Settings preview).
    func showSample(_ text: String) {
        cues = []
        shownID = nil
        textView.text = text
    }

    /// Bitmap cues are positioned in [0, 1] against the video frame (on a TV, the whole view; on a
    /// phone, the picture as it is fitted in the view), then scaled by the style's size about their
    /// bottom centre and kept on screen.
    private func frame(for image: SubtitleImage) -> CGRect {
        let p = image.position
        #if os(iOS)
        let area = Self.bitmapArea(for: image, videoSize: videoSize, pixelAspect: pixelAspect, in: bounds)
        #else
        let area = CGRect(origin: .zero, size: bounds.size)
        #endif
        let base = CGRect(x: area.minX + p.minX * area.width, y: area.minY + p.minY * area.height,
                          width: p.width * area.width, height: p.height * area.height)
        let scale = CGFloat(style.size)
        guard scale != 1, bounds.width > 0 else { return base }
        var scaled = CGRect(x: base.midX - base.width * scale / 2, y: base.maxY - base.height * scale,
                            width: base.width * scale, height: base.height * scale)
        scaled.origin.x = min(max(scaled.minX, 0), max(bounds.width - scaled.width, 0))
        scaled.origin.y = min(max(scaled.minY, 0), max(bounds.height - scaled.height, 0))
        return scaled
    }
}

/// One block of subtitle text in a `SubtitleStyle`: the label, its edge (shadow / outline)
/// and the optional box behind it. Shared by the player overlay and the Settings preview.
final class SubtitleTextView: UIView {
    private let label = UILabel()

    var text: String? {
        didSet { render() }
    }

    var style: SubtitleStyle = .default {
        didSet { if style != oldValue { render() } }
    }

    /// Multiplies the style's sizes, padding and corners (a phone's share of the TV's 1080p
    /// screen); 1 on a TV.
    var scale: CGFloat = 1 {
        didSet {
            guard scale != oldValue else { return }
            applyPadding()
            render()
        }
    }
    private var padding: [NSLayoutConstraint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous

        label.numberOfLines = 0
        label.textAlignment = .center
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOffset = .zero
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        padding = [
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ]
        NSLayoutConstraint.activate(padding)
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func applyPadding() {
        for (constraint, base) in zip(padding, [22, -22, 6, -8] as [CGFloat]) { constraint.constant = base * scale }
        layer.cornerRadius = 10 * scale
    }

    private func render() {
        let hasText = !(text?.isEmpty ?? true)
        isHidden = !hasText
        var drawn = style
        if scale != 1 { drawn.size *= Double(scale) }
        label.attributedText = text.map(drawn.attributed)
        backgroundColor = style.backgroundOpacity > 0 ? style.boxColor : .clear
        let shadow = style.edge == .shadow
        label.layer.shadowOpacity = shadow ? 1 : 0
        label.layer.shadowRadius = shadow ? 4 * CGFloat(max(style.size, 0.75)) * scale : 0
    }
}
