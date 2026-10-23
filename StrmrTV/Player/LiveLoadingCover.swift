import UIKit

/// The channel's logo and name over black until the first frame is up.
final class LiveLoadingCover: UIView {
    init(channel: LiveChannel, program: EPGProgram?) {
        super.init(frame: .zero)
        backgroundColor = .black
        let logo = UIImageView()
        logo.contentMode = .scaleAspectFit
        logo.translatesAutoresizingMaskIntoConstraints = false
        let title = UILabel()
        title.text = channel.name
        title.font = .preferredFont(forTextStyle: .title2)
        title.textColor = .white
        let subtitle = UILabel()
        subtitle.text = program?.title
        subtitle.font = .preferredFont(forTextStyle: .callout)
        subtitle.textColor = .lightGray
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = .white
        spinner.startAnimating()
        let stack = UIStackView(arrangedSubviews: [logo, title, subtitle, spinner])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: 320),
            logo.heightAnchor.constraint(equalToConstant: 180),
        ])
        if let url = channel.logoURL {
            Task { [weak logo] in
                let image = await ImagePipeline.load(url, size: CGSize(width: 320, height: 180), mode: .fit,
                                                     scale: ImagePipeline.scale)
                logo?.image = image
                logo?.isHidden = image == nil
            }
        } else {
            logo.isHidden = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
