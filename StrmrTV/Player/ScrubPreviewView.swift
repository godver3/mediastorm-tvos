import UIKit

/// Thumbnail + time card shown above the software HUD's progress bar while seeking.
final class ScrubPreviewView: UIView {
    static let imageSize = CGSize(width: 384, height: 216)

    private let imageView = UIImageView()
    private let timeLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.layer.cornerCurve = .continuous
        imageView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        imageView.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        imageView.layer.borderWidth = 1
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        timeLabel.textColor = .white
        timeLabel.textAlignment = .center
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.5
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 6)

        let stack = UIStackView(arrangedSubviews: [imageView, timeLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.widthAnchor.constraint(equalToConstant: Self.imageSize.width),
            imageView.heightAnchor.constraint(equalToConstant: Self.imageSize.height),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func set(time: String, image: UIImage?, showsImage: Bool) {
        timeLabel.text = time
        imageView.isHidden = !showsImage
        if let image { imageView.image = image }
    }

    func setImage(_ image: UIImage) {
        imageView.image = image
    }
}
