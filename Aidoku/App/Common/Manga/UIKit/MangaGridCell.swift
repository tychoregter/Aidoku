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

    var subtitle: String? {
        get { subtitleLabel.text }
        set { subtitleLabel.text = newValue }
    }

    var showsCaption = false {
        didSet {
            guard showsCaption != oldValue else { return }
            coverBottomConstraint?.isActive = !showsCaption
            coverAspectConstraint?.isActive = showsCaption
            titleLabel.isHidden = !showsCaption || isPlaceholder
            subtitleLabel.isHidden = !showsCaption || isPlaceholder
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

    let coverView = UIView()
    let imageView = GIFImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let placeholderIconView = UIImageView()
    private let placeholderLabel = UILabel()
    private let placeholderStackView = UIStackView()
    private let overlayView = UIView()
    private let gradient = CAGradientLayer()
    private let nsfwCoverView: NSFWCoverView = {
        let view = NSFWCoverView()
        view.iconOnlySize = 40
        return view
    }()

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
        shadowOverlayView.layer.cornerRadius = 12
        shadowOverlayView.translatesAutoresizingMaskIntoConstraints = false
        return shadowOverlayView
    }()

    private lazy var selectionView = SelectionCheckView(style: .bordered)

    private var badgeConstraints: [NSLayoutConstraint] = []
    private var placeholderLeadingConstraint: NSLayoutConstraint?
    private var placeholderTrailingConstraint: NSLayoutConstraint?
    private var coverBottomConstraint: NSLayoutConstraint?
    private var coverAspectConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 12
        coverView.layer.cornerCurve = .continuous
        coverView.layer.borderWidth = MangaCoverBorderStyle.width(for: traitCollection)
        updatePosterBorderAppearance()
        contentView.addSubview(coverView)

        imageView.image = UIImage(named: "MangaPlaceholder")
        imageView.backgroundColor = Self.coverBackgroundColor
        imageView.contentMode = .scaleAspectFill
        coverView.addSubview(imageView)
        coverView.addSubview(nsfwCoverView)

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
        coverView.addSubview(placeholderStackView)

        gradient.frame = bounds
        gradient.locations = [0.6, 1]
        gradient.colors = [
            UIColor(white: 0, alpha: 0).cgColor,
            UIColor(white: 0, alpha: 0.7).cgColor
        ]
        gradient.cornerRadius = 12
        gradient.needsDisplayOnBoundsChange = true

        // Keep artwork unobstructed; the optional caption sits below the cover.
        overlayView.layer.cornerRadius = 12
        coverView.addSubview(overlayView)

        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.font = .systemFont(ofSize: 13.25, weight: .medium)
        contentView.addSubview(titleLabel)
        titleLabel.isHidden = true
        overlayView.isHidden = true

        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = .systemFont(ofSize: 14)
        contentView.addSubview(subtitleLabel)
        subtitleLabel.isHidden = true

        coverView.addSubview(badgeView)

        bookmarkView.isHidden = true
        bookmarkView.image = UIImage(named: "bookmark")
        bookmarkView.contentMode = .scaleAspectFit
        coverView.addSubview(bookmarkView)

        highlightView.alpha = 0
        highlightView.backgroundColor = UIColor(white: 0, alpha: 0.5)
        highlightView.layer.cornerRadius = 12
        coverView.addSubview(highlightView)

        selectionView.isHidden = true

        coverView.addSubview(shadowOverlayView)
        coverView.addSubview(selectionView)
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
            coverView.layer.borderColor = UIColor.clear.cgColor
            return
        }
        coverView.layer.borderColor = MangaCoverBorderStyle.color(for: traitCollection).cgColor
    }

    private func updatePlaceholderAppearance() {
        guard isPlaceholder else { return }
        let background = Self.coverBackgroundColor.resolvedColor(with: traitCollection)
        let foreground = NSFWCoverView.foregroundColor(for: background)
        coverView.backgroundColor = background
        placeholderIconView.tintColor = foreground
        placeholderLabel.textColor = foreground
    }

    func constrain() {
        coverView.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        nsfwCoverView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderStackView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        bookmarkView.translatesAutoresizingMaskIntoConstraints = false
        highlightView.translatesAutoresizingMaskIntoConstraints = false
        selectionView.translatesAutoresizingMaskIntoConstraints = false

        coverBottomConstraint = coverView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        coverAspectConstraint = coverView.heightAnchor.constraint(equalTo: coverView.widthAnchor, multiplier: 1.5)
        coverBottomConstraint?.isActive = true

        NSLayoutConstraint.activate([
            coverView.topAnchor.constraint(equalTo: contentView.topAnchor),
            coverView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            coverView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            imageView.topAnchor.constraint(equalTo: coverView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: coverView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: coverView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: coverView.bottomAnchor),

            nsfwCoverView.topAnchor.constraint(equalTo: coverView.topAnchor),
            nsfwCoverView.leadingAnchor.constraint(equalTo: coverView.leadingAnchor),
            nsfwCoverView.trailingAnchor.constraint(equalTo: coverView.trailingAnchor),
            nsfwCoverView.bottomAnchor.constraint(equalTo: coverView.bottomAnchor),

            placeholderStackView.centerYAnchor.constraint(equalTo: coverView.centerYAnchor),
            placeholderIconView.widthAnchor.constraint(equalToConstant: 22),
            placeholderIconView.heightAnchor.constraint(equalToConstant: 22),

            overlayView.topAnchor.constraint(equalTo: coverView.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: coverView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: coverView.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: coverView.bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: coverView.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),

            badgeView.heightAnchor.constraint(equalToConstant: 24),
            badgeView.topAnchor.constraint(equalTo: coverView.topAnchor, constant: 6),
            badgeView.leadingAnchor.constraint(equalTo: coverView.leadingAnchor, constant: 6),

            bookmarkView.trailingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: -8),
            bookmarkView.topAnchor.constraint(equalTo: coverView.topAnchor),
            bookmarkView.widthAnchor.constraint(equalToConstant: 17),
            bookmarkView.heightAnchor.constraint(equalToConstant: 27),

            highlightView.topAnchor.constraint(equalTo: coverView.topAnchor),
            highlightView.leftAnchor.constraint(equalTo: coverView.leftAnchor),
            highlightView.trailingAnchor.constraint(equalTo: coverView.trailingAnchor),
            highlightView.bottomAnchor.constraint(equalTo: coverView.bottomAnchor),

            shadowOverlayView.topAnchor.constraint(equalTo: coverView.topAnchor),
            shadowOverlayView.leadingAnchor.constraint(equalTo: coverView.leadingAnchor),
            shadowOverlayView.trailingAnchor.constraint(equalTo: coverView.trailingAnchor),
            shadowOverlayView.bottomAnchor.constraint(equalTo: coverView.bottomAnchor),

            selectionView.rightAnchor.constraint(equalTo: coverView.rightAnchor, constant: -10),
            selectionView.bottomAnchor.constraint(equalTo: coverView.bottomAnchor, constant: -10),
            selectionView.widthAnchor.constraint(equalToConstant: 24),
            selectionView.heightAnchor.constraint(equalToConstant: 24)
        ])
        placeholderLeadingConstraint = placeholderStackView.leadingAnchor.constraint(
            equalTo: coverView.leadingAnchor,
            constant: 12
        )
        placeholderTrailingConstraint = placeholderStackView.trailingAnchor.constraint(
            equalTo: coverView.trailingAnchor,
            constant: -12
        )
        placeholderLeadingConstraint?.isActive = true
        placeholderTrailingConstraint?.isActive = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = coverView.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        url = nil
        imageView.image = UIImage(named: "MangaPlaceholder")
        originalCoverImage = nil
        grayscalesCaughtUpCover = false
        showsCaption = false
        subtitle = nil
        imageTask?.cancel()
        imageTask = nil
        highlightView.alpha = 0
        setNSFW(false, title: nil)
        setPlaceholder(nil)
    }

    func setNSFW(_ isNSFW: Bool, title: String?, developerMode: Bool = false) {
        let hidesNSFW = isNSFW && AppSettings.appearance.blurNSFWCovers.get()
        hidesNSFWCover = hidesNSFW || developerMode
        nsfwCoverView.isHidden = !hidesNSFWCover
        updatePosterBorderAppearance()
        guard hidesNSFWCover else { return }
        nsfwCoverView.presentation = hidesNSFW
            ? (AppSettings.library.hideCoverTitles.get() ? .title : .iconOnly)
            : .blank
        nsfwCoverView.layer.cornerRadius = coverView.layer.cornerRadius
        nsfwCoverView.layer.cornerCurve = .continuous
        nsfwCoverView.configure(title: title, image: imageView.image)
        coverView.bringSubviewToFront(nsfwCoverView)
        coverView.bringSubviewToFront(highlightView)
        coverView.bringSubviewToFront(shadowOverlayView)
        coverView.bringSubviewToFront(selectionView)
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
        titleLabel.isHidden = !showsCaption || isPlaceholder
        subtitleLabel.isHidden = !showsCaption || isPlaceholder
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
        coverView.backgroundColor = isPlaceholder ? Self.coverBackgroundColor : .clear
        if isPlaceholder {
            updatePlaceholderAppearance()
            coverView.bringSubviewToFront(placeholderStackView)
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
        if let color = image.dominantColor() {
            CoverPalette.remember(color, for: url.absoluteString)
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
                        if self.hidesNSFWCover, let color = response.image.dominantColor() {
                            CoverPalette.remember(color, for: url.absoluteString)
                        }
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
    enum Presentation {
        case title
        case iconOnly
        case blank
    }

    var presentation: Presentation = .title {
        didSet { updatePresentation() }
    }
    var iconOnlySize: CGFloat = 32 {
        didSet { updatePresentation() }
    }
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let stackView = UIStackView()
    private var coverColor = UIColor.secondarySystemBackground
    private var iconWidth: NSLayoutConstraint!
    private var iconHeight: NSLayoutConstraint!

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

        iconWidth = iconView.widthAnchor.constraint(equalToConstant: 22)
        iconHeight = iconView.heightAnchor.constraint(equalToConstant: 22)
        NSLayoutConstraint.activate([
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconWidth,
            iconHeight
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String?, image: UIImage?) {
        titleLabel.text = title ?? NSLocalizedString("UNTITLED")
        coverColor = image?.dominantColor() ?? UIColor.secondarySystemBackground
        updatePresentation()
        updateAppearance()
    }

    private func updatePresentation() {
        iconView.isHidden = presentation == .blank
        titleLabel.isHidden = presentation != .title
        let size: CGFloat = presentation == .iconOnly ? iconOnlySize : 22
        iconWidth?.constant = size
        iconHeight?.constant = size
        iconView.image = UIImage(
            systemName: "eye.slash",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        )
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
        let background = Self.backgroundColor(for: baseColor, isDark: isDark)
        backgroundColor = background

        let foreground = Self.foregroundColor(for: background)
        iconView.tintColor = foreground
        titleLabel.textColor = foreground

        layer.borderWidth = MangaCoverBorderStyle.width(for: traitCollection)
        layer.borderColor = Self.blend(
            background,
            toward: isDark ? .white : .black,
            amount: isDark ? 0.24 : 0.18
        ).withAlphaComponent(0.72).cgColor
    }

    static func backgroundColor(for baseColor: UIColor, isDark: Bool) -> UIColor {
        blend(
            baseColor,
            toward: isDark ? .black : .white,
            amount: isDark ? 0.18 : 0.20
        )
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
