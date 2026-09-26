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
    private let nsfwCoverView = NSFWCoverView()

    private lazy var badgeView = DoubleBadgeView()

    private let bookmarkView = UIImageView()
    private let highlightView = UIView()

    private var url: String?
    private var imageTask: ImageTask?
    var isEditing = false
    private var isPlaceholder = false
    private var hidesNSFWCover = false
    private var originalCoverImage: UIImage?
    private var grayscalesCaughtUpCover = false

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
        contentView.addSubview(nsfwCoverView)

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
            updatePlaceholderAppearance()
        }
    }

    private func updatePosterBorderAppearance() {
        guard !hidesNSFWCover else {
            contentView.layer.borderColor = UIColor.clear.cgColor
            return
        }
        let borderColor = traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.24)
            : UIColor.black.withAlphaComponent(0.18)
        contentView.layer.borderColor = borderColor.cgColor
    }

    private func updatePlaceholderAppearance() {
        guard isPlaceholder else { return }
        let background = Self.coverBackgroundColor.resolvedColor(with: traitCollection)
        let foreground = NSFWCoverView.foregroundColor(for: background)
        contentView.backgroundColor = background
        placeholderIconView.tintColor = foreground
        placeholderLabel.textColor = foreground
    }

    func constrain() {
        imageView.translatesAutoresizingMaskIntoConstraints = false
        nsfwCoverView.translatesAutoresizingMaskIntoConstraints = false
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

            nsfwCoverView.topAnchor.constraint(equalTo: contentView.topAnchor),
            nsfwCoverView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            nsfwCoverView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            nsfwCoverView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

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
        url = nil
        imageView.image = UIImage(named: "MangaPlaceholder")
        originalCoverImage = nil
        grayscalesCaughtUpCover = false
        imageTask?.cancel()
        imageTask = nil
        highlightView.alpha = 0
        setNSFW(false, title: nil)
        setPlaceholder(nil)
    }

    func setNSFW(_ isNSFW: Bool, title: String?) {
        hidesNSFWCover = isNSFW && AppSettings.appearance.blurNSFWCovers.get()
        nsfwCoverView.isHidden = !hidesNSFWCover
        updatePosterBorderAppearance()
        guard hidesNSFWCover else { return }
        nsfwCoverView.layer.cornerRadius = contentView.layer.cornerRadius
        nsfwCoverView.layer.cornerCurve = .continuous
        nsfwCoverView.configure(title: title, image: imageView.image)
        contentView.bringSubviewToFront(nsfwCoverView)
        contentView.bringSubviewToFront(highlightView)
        contentView.bringSubviewToFront(shadowOverlayView)
        contentView.bringSubviewToFront(selectionView)
    }

    func setCaughtUp(_ isCaughtUp: Bool) {
        grayscalesCaughtUpCover = isCaughtUp && AppSettings.appearance.grayscaleCaughtUpCovers.get()
        if grayscalesCaughtUpCover {
            imageView.stopAnimatingGIF()
        }
        updateCoverImage()
    }

    private func updateCoverImage() {
        guard let originalCoverImage else { return }
        imageView.image = grayscalesCaughtUpCover
            ? MangaCoverImageAppearance.grayscale(originalCoverImage)
            : originalCoverImage
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
        contentView.backgroundColor = isPlaceholder ? Self.coverBackgroundColor : .clear
        if isPlaceholder {
            updatePlaceholderAppearance()
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
    func showCachedImage(url: URL?) {
        guard let url else { return }
        let imageURL = url.toAidokuFileUrl() ?? url
        self.url = imageURL.absoluteString
        let request = ImageRequest(
            urlRequest: URLRequest(url: imageURL),
            processors: [CoverDownsampleProcessor(shortestSide: 630)]
        )
        guard let image = ImagePipeline.shared.cache.cachedImage(for: request, caches: [.memory])?.image else {
            return
        }
        originalCoverImage = image
        updateCoverImage()
        if hidesNSFWCover {
            nsfwCoverView.configure(title: title, image: image)
        }
    }

    func loadImage(url: URL?) async {
        guard let url else { return }

        if let imageTask, imageTask.state == .running {
            return
        }

        self.imageView.stopAnimatingGIF()

        let currentIdentifier = identifier
        let source: AidokuRunner.Source? = if let sourceKey = currentIdentifier?.sourceKey {
            await SourceManager.shared.source(for: sourceKey)
        } else {
            nil
        }

        guard identifier == currentIdentifier else { return }

        var urlRequest = URLRequest(url: url)
        var cached = ImagePipeline.shared.cache.containsCachedImage(for: .init(urlRequest: urlRequest))

        if !cached {
            if let fileUrl = url.toAidokuFileUrl() {
                urlRequest = URLRequest(url: fileUrl)
            } else if let source {
                urlRequest = await source.getModifiedImageRequest(url: url, context: nil)
            }
        }

        guard identifier == currentIdentifier else { return }

        self.url = (urlRequest.url ?? url).absoluteString

        var processors: [ImageProcessing] = [CoverDownsampleProcessor(shortestSide: 630)]
        if let source, source.features.processesCovers {
            processors.append(CoverInterceptorProcessor(source: source))
        }

        let request = ImageRequest(
            urlRequest: urlRequest,
            processors: processors,
            userInfo: [.processesKey: source?.features.processesCovers ?? false]
        )
        let storesProcessedCover = source?.features.processesCovers != true

        cached = cached || ImagePipeline.shared.cache.containsCachedImage(for: request)

        imageTask = ImagePipeline.shared.loadImage(with: request) { [weak self] result in
            guard let self else { return }
            switch result {
                case .success(let response):
                    if response.request.imageID != self.url {
                        return
                    }
                    if storesProcessedCover {
                        Task.detached(priority: .utility) {
                            await CoverProcessedCacheWriter.shared.store(response.container, for: request)
                        }
                    }
                    Task { @MainActor in
                        self.originalCoverImage = response.image
                        let coverImage = self.grayscalesCaughtUpCover
                            ? MangaCoverImageAppearance.grayscale(response.image)
                            : response.image
                        if cached {
                            self.imageView.image = coverImage
                        } else {
                            UIView.transition(with: self.imageView, duration: 0.3, options: .transitionCrossDissolve) {
                                self.imageView.image = coverImage
                            }
                        }
                        if !self.grayscalesCaughtUpCover,
                           response.container.type == .gif,
                           let data = response.container.data {
                            self.imageView.animate(withGIFData: data)
                        }
                        if self.hidesNSFWCover {
                            self.nsfwCoverView.configure(title: self.title, image: response.image)
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

enum MangaCoverImageAppearance {
    private static let grayscaleCache: NSCache<UIImage, UIImage> = {
        let cache = NSCache<UIImage, UIImage>()
        cache.totalCostLimit = 64 * 1_024 * 1_024
        return cache
    }()

    static func grayscale(_ image: UIImage) -> UIImage {
        if let cachedImage = grayscaleCache.object(forKey: image) {
            return cachedImage
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let bounds = CGRect(origin: .zero, size: image.size)
        let grayscaleImage = UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            image.draw(in: bounds)
            context.cgContext.setBlendMode(.saturation)
            context.cgContext.setFillColor(UIColor.black.cgColor)
            context.cgContext.fill(bounds)
        }
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        grayscaleCache.setObject(
            grayscaleImage,
            forKey: image,
            cost: Int(pixelWidth * pixelHeight * 4)
        )
        return grayscaleImage
    }
}

final class NSFWCoverView: UIView {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let stackView = UIStackView()
    private var coverColor = UIColor.secondarySystemBackground

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true

        iconView.contentMode = .scaleAspectFit
        iconView.image = UIImage(
            systemName: "eye.slash",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        )

        titleLabel.textAlignment = .center
        titleLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 14, weight: .medium)
        )
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail

        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(titleLabel)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String?, image: UIImage?) {
        titleLabel.text = title ?? NSLocalizedString("UNTITLED")
        coverColor = image?.dominantColor() ?? UIColor.secondarySystemBackground
        updateAppearance()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            updateAppearance()
        }
    }

    private func updateAppearance() {
        let baseColor = coverColor.resolvedColor(with: traitCollection)
        let isDark = traitCollection.userInterfaceStyle == .dark
        let background = Self.blend(
            baseColor,
            toward: isDark ? .black : .white,
            amount: isDark ? 0.18 : 0.20
        )
        backgroundColor = background

        let foreground = Self.foregroundColor(for: background)
        iconView.tintColor = foreground
        titleLabel.textColor = foreground

        layer.borderWidth = 1
        layer.borderColor = Self.blend(
            background,
            toward: isDark ? .white : .black,
            amount: isDark ? 0.24 : 0.18
        ).withAlphaComponent(0.72).cgColor
    }

    static func foregroundColor(for color: UIColor) -> UIColor {
        let components = rgbaComponents(of: color)
        let luminance = 0.2126 * components.red
            + 0.7152 * components.green
            + 0.0722 * components.blue
        return blend(
            color,
            toward: luminance > 0.58 ? .black : .white,
            amount: luminance > 0.58 ? 0.68 : 0.72
        ).withAlphaComponent(0.72)
    }

    private static func blend(_ color: UIColor, toward target: UIColor, amount: CGFloat) -> UIColor {
        let source = rgbaComponents(of: color)
        let destination = rgbaComponents(of: target)
        return UIColor(
            red: source.red + (destination.red - source.red) * amount,
            green: source.green + (destination.green - source.green) * amount,
            blue: source.blue + (destination.blue - source.blue) * amount,
            alpha: 1
        )
    }

    private static func rgbaComponents(of color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: nil)
        return (red, green, blue)
    }
}
