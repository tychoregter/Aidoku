//
//  MangaGridCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 7/24/22.
//

import AidokuRunner
import Gifu
import Nuke
import UIKit

class MangaGridCell: UICollectionViewCell {
    var identifier: MangaIdentifier?

    var title: String? {
        get {
            titleLabel.text
        }
        set {
            titleLabel.text = newValue ?? NSLocalizedString("UNTITLED")
        }
    }

    var showsBookmark: Bool {
        get {
            !bookmarkView.isHidden
        }
        set {
            bookmarkView.isHidden = !newValue
        }
    }

    var badgeNumber: Int {
        get { badgeView.badgeNumber }
        set { badgeView.badgeNumber = newValue }
    }
    var badgeNumber2: Int {
        get { badgeView.badgeNumber2 }
        set { badgeView.badgeNumber2 = newValue }
    }

    let imageView = GIFImageView()
    private let titleLabel = UILabel()
    private let placeholderIconView = UIImageView()
    private let placeholderLabel = UILabel()
    private let placeholderStackView = UIStackView()
    private let overlayView = UIView()
    private let gradient = CAGradientLayer()

    private lazy var badgeView = DoubleBadgeView()

    private let bookmarkView = UIImageView()
    private let highlightView = UIView()

    private var url: String?
    private var imageTask: ImageTask?
    var isEditing = false
    private var isPlaceholder = false

    // shadow shown when in selection mode
    private lazy var shadowOverlayView: UIView = {
        let shadowOverlayView = UIView()
        shadowOverlayView.alpha = 0
        shadowOverlayView.backgroundColor = UIColor(white: 0, alpha: 0.5)
        shadowOverlayView.layer.cornerRadius = layer.cornerRadius
        shadowOverlayView.translatesAutoresizingMaskIntoConstraints = false
        return shadowOverlayView
    }()

    private lazy var selectionView = SelectionCheckView(style: .bordered)

    private var badgeConstraints: [NSLayoutConstraint] = []
    private var placeholderLeadingConstraint: NSLayoutConstraint?
    private var placeholderTrailingConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        contentView.clipsToBounds = true
        contentView.layer.cornerRadius = 12
        contentView.layer.cornerCurve = .continuous
        contentView.layer.borderWidth = 1
        updatePosterBorderAppearance()

        imageView.image = UIImage(named: "MangaPlaceholder")
        imageView.backgroundColor = Self.coverBackgroundColor
        imageView.contentMode = .scaleAspectFill
        contentView.addSubview(imageView)

        placeholderIconView.tintColor = .tertiaryLabel
        placeholderIconView.contentMode = .scaleAspectFit

        placeholderLabel.textAlignment = .center
        placeholderLabel.textColor = .tertiaryLabel
        placeholderLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 14, weight: .medium)
        )
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.numberOfLines = 0

        placeholderStackView.axis = .vertical
        placeholderStackView.alignment = .center
        placeholderStackView.spacing = 8
        placeholderStackView.addArrangedSubview(placeholderIconView)
        placeholderStackView.addArrangedSubview(placeholderLabel)
        placeholderStackView.isHidden = true
        contentView.addSubview(placeholderStackView)

        gradient.frame = bounds
        gradient.locations = [0.6, 1]
        gradient.colors = [
            UIColor(white: 0, alpha: 0).cgColor,
            UIColor(white: 0, alpha: 0.7).cgColor
        ]
        gradient.cornerRadius = layer.cornerRadius
        gradient.needsDisplayOnBoundsChange = true

        // Keep the poster image clean; titles are shown below cards by the
        // surrounding library/list layout rather than over the artwork.
        overlayView.layer.cornerRadius = layer.cornerRadius
        contentView.addSubview(overlayView)

        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        contentView.addSubview(titleLabel)
        titleLabel.isHidden = true
        overlayView.isHidden = true

        contentView.addSubview(badgeView)

        bookmarkView.isHidden = true
        bookmarkView.image = UIImage(named: "bookmark")
        bookmarkView.contentMode = .scaleAspectFit
        contentView.addSubview(bookmarkView)

        highlightView.alpha = 0
        highlightView.backgroundColor = UIColor(white: 0, alpha: 0.5)
        highlightView.layer.cornerRadius = layer.cornerRadius
        contentView.addSubview(highlightView)

        selectionView.isHidden = true

        contentView.addSubview(shadowOverlayView)
        contentView.addSubview(selectionView)
    }

    private static let coverBackgroundColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 28.0 / 255.0, green: 28.0 / 255.0, blue: 30.0 / 255.0, alpha: 1)
            : UIColor(red: 241.0 / 255.0, green: 241.0 / 255.0, blue: 246.0 / 255.0, alpha: 1)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            updatePosterBorderAppearance()
        }
    }

    private func updatePosterBorderAppearance() {
        let borderColor = traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.24)
            : UIColor.black.withAlphaComponent(0.18)
        contentView.layer.borderColor = borderColor.cgColor
    }

    func constrain() {
        imageView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderStackView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        bookmarkView.translatesAutoresizingMaskIntoConstraints = false
        highlightView.translatesAutoresizingMaskIntoConstraints = false
        selectionView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            placeholderStackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            placeholderIconView.widthAnchor.constraint(equalToConstant: 22),
            placeholderIconView.heightAnchor.constraint(equalToConstant: 22),

            overlayView.topAnchor.constraint(equalTo: contentView.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            badgeView.heightAnchor.constraint(equalToConstant: 24),
            badgeView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            badgeView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),

            bookmarkView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            bookmarkView.topAnchor.constraint(equalTo: contentView.topAnchor),
            bookmarkView.widthAnchor.constraint(equalToConstant: 17),
            bookmarkView.heightAnchor.constraint(equalToConstant: 27),

            highlightView.topAnchor.constraint(equalTo: contentView.topAnchor),
            highlightView.leftAnchor.constraint(equalTo: contentView.leftAnchor),
            highlightView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            highlightView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            shadowOverlayView.topAnchor.constraint(equalTo: contentView.topAnchor),
            shadowOverlayView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            shadowOverlayView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            shadowOverlayView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            selectionView.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -10),
            selectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            selectionView.widthAnchor.constraint(equalToConstant: 24),
            selectionView.heightAnchor.constraint(equalToConstant: 24)
        ])
        placeholderLeadingConstraint = placeholderStackView.leadingAnchor.constraint(
            equalTo: contentView.leadingAnchor,
            constant: 12
        )
        placeholderTrailingConstraint = placeholderStackView.trailingAnchor.constraint(
            equalTo: contentView.trailingAnchor,
            constant: -12
        )
        placeholderLeadingConstraint?.isActive = true
        placeholderTrailingConstraint?.isActive = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = contentView.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = UIImage(named: "MangaPlaceholder")
        imageTask?.cancel()
        imageTask = nil
        highlightView.alpha = 0
        setPlaceholder(nil)
    }

    func setPlaceholder(
        _ text: String?,
        symbolName: String? = nil,
        horizontalPadding: CGFloat = 12
    ) {
        isPlaceholder = text != nil
        placeholderLabel.text = text
        placeholderIconView.image = symbolName.flatMap {
            UIImage(
                systemName: $0,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
            )
        }
        placeholderStackView.isHidden = !isPlaceholder
        placeholderLeadingConstraint?.constant = horizontalPadding
        placeholderTrailingConstraint?.constant = -horizontalPadding
        imageView.isHidden = isPlaceholder
        badgeView.isHidden = isPlaceholder
        bookmarkView.isHidden = true
        selectionView.isHidden = isPlaceholder || !isEditing
        shadowOverlayView.isHidden = isPlaceholder
        contentView.backgroundColor = isPlaceholder
            ? UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 28.0 / 255.0, green: 28.0 / 255.0, blue: 30.0 / 255.0, alpha: 1)
                    : UIColor(red: 241.0 / 255.0, green: 241.0 / 255.0, blue: 246.0 / 255.0, alpha: 1)
            }
            : .clear
        if isPlaceholder {
            contentView.bringSubviewToFront(placeholderStackView)
        }
    }
}

extension MangaGridCell {
    func highlight() {
        guard !isPlaceholder else { return }
        highlightView.alpha = 1
    }

    func unhighlight(animated: Bool = true) {
        UIView.animate(withDuration: animated ? 0.3 : 0) {
            self.highlightView.alpha = 0
        }
    }

    func setEditing(_ editing: Bool, animated: Bool = true) {
        guard !isPlaceholder else { return }
        guard isEditing != editing else { return }
        isEditing = editing
        if editing {
            selectionView.setSelected(false, animated: false)
        }
        if animated {
            if editing {
                self.selectionView.isHidden = false
            }
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.shadowOverlayView.alpha = editing ? 1 : 0
            } completion: { _ in
                if !editing {
                    self.selectionView.isHidden = true
                }
            }
        } else {
            self.shadowOverlayView.alpha = editing ? 1 : 0
            self.selectionView.isHidden = !editing
        }
    }

    func setSelected(_ selected: Bool, animated: Bool = true) {
        guard isEditing else { return }
        selectionView.setSelected(selected, animated: animated)
        if animated {
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.shadowOverlayView.alpha = selected ? 0 : 1
            }
        } else {
            self.shadowOverlayView.alpha = selected ? 0 : 1
        }
    }
}

extension MangaGridCell {
    func loadImage(url: URL?) async {
        guard let url else { return }

        if let imageTask, imageTask.state == .running {
            return
        }

        self.imageView.stopAnimatingGIF()

        let source: AidokuRunner.Source? = if let sourceKey = identifier?.sourceKey {
            await SourceManager.shared.source(for: sourceKey)
        } else {
            nil
        }

        var urlRequest = URLRequest(url: url)
        var cached = ImagePipeline.shared.cache.containsCachedImage(for: .init(urlRequest: urlRequest))

        if !cached {
            if let fileUrl = url.toAidokuFileUrl() {
                urlRequest = URLRequest(url: fileUrl)
            } else if let source {
                urlRequest = await source.getModifiedImageRequest(url: url, context: nil)
            }
        }

        self.url = (urlRequest.url ?? url).absoluteString

        var processors: [ImageProcessing] = [DownsampleProcessor(width: bounds.width)]
        if let source, source.features.processesCovers {
            processors.append(CoverInterceptorProcessor(source: source))
        }

        let request = ImageRequest(
            urlRequest: urlRequest,
            processors: processors,
            userInfo: [.processesKey: source?.features.processesCovers ?? false]
        )

        cached = cached || ImagePipeline.shared.cache.containsCachedImage(for: request)

        imageTask = ImagePipeline.shared.loadImage(with: request) { [weak self] result in
            guard let self else { return }
            switch result {
                case .success(let response):
                    if response.request.imageID != self.url {
                        return
                    }
                    Task { @MainActor in
                        if cached {
                            self.imageView.image = response.image
                        } else {
                            UIView.transition(with: self.imageView, duration: 0.3, options: .transitionCrossDissolve) {
                                self.imageView.image = response.image
                            }
                        }
                        if response.container.type == .gif, let data = response.container.data {
                            self.imageView.animate(withGIFData: data)
                        }
                    }
                case .failure(let error):
                    imageTask = nil
                    guard let identifier else { return }
                    Task { @MainActor [weak self] in
                        guard
                            let newUrl = await CoverRecovery.recover(from: error, identifier: identifier),
                            self?.identifier == identifier
                        else { return }
                        await self?.loadImage(url: newUrl)
                    }
            }
        }
    }
}
