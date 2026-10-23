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
    private var cues: [SubtitleCue] = []
    private var shownID: Int?
    private var shownImage: SubtitleImage?
    private var lastSourceTime: Double = 0

    var style: SubtitleStyle = .default {
        didSet {
            guard style != oldValue else { return }
            textView.style = style
            bottomConstraint.constant = -style.bottomMargin
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
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 160),
            textView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -160),
            textView.centerXAnchor.constraint(equalTo: centerXAnchor),
            bottomConstraint,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
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

    /// Bitmap cues are positioned in [0, 1] against the video frame, which fills this view,
    /// then scaled by the style's size about their bottom centre and kept on screen.
    private func frame(for image: SubtitleImage) -> CGRect {
        let p = image.position
        let base = CGRect(x: p.minX * bounds.width, y: p.minY * bounds.height,
                          width: p.width * bounds.width, height: p.height * bounds.height)
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
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func render() {
        let hasText = !(text?.isEmpty ?? true)
        isHidden = !hasText
        label.attributedText = text.map(style.attributed)
        backgroundColor = style.backgroundOpacity > 0 ? style.boxColor : .clear
        let shadow = style.edge == .shadow
        label.layer.shadowOpacity = shadow ? 1 : 0
        label.layer.shadowRadius = shadow ? 4 * CGFloat(max(style.size, 0.75)) : 0
    }
}
