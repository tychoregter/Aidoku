//
//  ReaderThumbnailScrubberView.swift
//  Aidoku
//

import UIKit

/// An Apple Books-inspired page scrubber that keeps the reader's existing
/// normalized (0...1) progress API while presenting the chapter as thumbnails.
final class ReaderThumbnailScrubberView: UIControl {
    private enum Metrics {
        static let horizontalInset: CGFloat = 22
        static let trackHeight: CGFloat = 20
        static let selectedPageHeight: CGFloat = 30
        static let pageAspectRatio: CGFloat = 0.70
        static let previewWidth: CGFloat = 82
        static let previewImageHeight: CGFloat = 108
        static let previewLabelHeight: CGFloat = 30
        static let previewSpacing: CGFloat = 8
    }

    var direction: ReaderSliderView.SliderDirection = .forward {
        didSet {
            guard oldValue != direction else { return }
            layoutThumbnailViews()
            updatePreviewPosition()
        }
    }

    var minimumValue: CGFloat = 0
    var maximumValue: CGFloat = 1
    var onPreviewVisibilityChange: ((Bool) -> Void)?
    var currentValue: CGFloat = 0 {
        didSet {
            let boundedValue = min(max(currentValue, minimumValue), maximumValue)
            if currentValue != boundedValue {
                currentValue = boundedValue
                return
            }
            updatePreviewPosition()
        }
    }

    private let trackView = UIView()
    private let thumbnailContainer = UIView()
    private let selectionView = UIView()
    private let selectedThumbnailView = UIImageView()
    private let previewContainer = UIVisualEffectView()
    private let previewImageView = UIImageView()
    private let previewLabel = UILabel()

    private var pageCount = 0
    private var thumbnailViews: [UIImageView] = []
    private var thumbnailTasks: [Task<Void, Never>] = []
    private var loadingIndexes: Set<Int> = []
    private var thumbnailProvider: ((Int) async -> UIImage?)?
    private var loadedImages: [Int: UIImage] = [:]
    private var displayedPreviewIndex: Int?

    /// The width needed to show every page as a page-shaped thumbnail rather
    /// than stretching a short chapter across the whole reader overlay.
    var preferredWidth: CGFloat? {
        guard pageCount > 0 else { return nil }
        return Metrics.horizontalInset * 2
            + CGFloat(pageCount) * maximumThumbnailWidth
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        thumbnailTasks.forEach { $0.cancel() }
    }

    func configure(pageCount: Int, thumbnailProvider: @escaping (Int) async -> UIImage?) {
        thumbnailTasks.forEach { $0.cancel() }
        thumbnailTasks.removeAll()
        thumbnailViews.forEach { $0.removeFromSuperview() }
        thumbnailViews.removeAll()
        loadedImages.removeAll()
        loadingIndexes.removeAll()
        displayedPreviewIndex = nil

        self.pageCount = pageCount
        self.thumbnailProvider = thumbnailProvider

        guard pageCount > 0 else { return }
        thumbnailViews = (0..<pageCount).map { index in
            let imageView = UIImageView()
            imageView.backgroundColor = .tertiarySystemFill
            // Keep every thumbnail at the strip's full height. Pages that are
            // wider than their slot are cropped evenly at the sides.
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.accessibilityIdentifier = "reader-thumbnail-\(index)"
            thumbnailContainer.addSubview(imageView)
            return imageView
        }
        setNeedsLayout()
        loadVisibleThumbnails()
    }

    func move(toValue value: CGFloat) {
        currentValue = value
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let trackWidth = max(0, bounds.width - Metrics.horizontalInset * 2)
        let opticalCenterOffset = 0.5 / max(traitCollection.displayScale, 1)
        trackView.frame = CGRect(
            x: Metrics.horizontalInset,
            y: (bounds.height - Metrics.trackHeight) / 2 + opticalCenterOffset,
            width: trackWidth,
            height: Metrics.trackHeight
        )
        thumbnailContainer.frame = trackView.bounds
        trackView.layer.cornerRadius = 2
        selectionView.layer.cornerRadius = 2
        layoutThumbnailViews()

        let previewHeight = Metrics.previewImageHeight + Metrics.previewLabelHeight
        previewContainer.bounds = CGRect(x: 0, y: 0, width: Metrics.previewWidth, height: previewHeight)
        previewImageView.frame = CGRect(x: 0, y: 0, width: Metrics.previewWidth, height: Metrics.previewImageHeight)
        previewLabel.frame = CGRect(
            x: 0,
            y: Metrics.previewImageHeight,
            width: Metrics.previewWidth,
            height: Metrics.previewLabelHeight
        )
        previewContainer.layer.cornerRadius = 16
        updatePreviewPosition()
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard pageCount > 0 else { return false }
        previewContainer.isHidden = false
        previewContainer.alpha = 0
        onPreviewVisibilityChange?(true)
        updateValue(at: touch.location(in: self))
        UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
            self.previewContainer.alpha = 1
        }
        sendActions(for: .valueChanged)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateValue(at: touch.location(in: self))
        sendActions(for: .valueChanged)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        hidePreview()
        sendActions(for: .editingDidEnd)
    }

    override func cancelTracking(with event: UIEvent?) {
        hidePreview()
        sendActions(for: .editingDidEnd)
    }

    private func configure() {
        clipsToBounds = false
        isExclusiveTouch = true

        trackView.backgroundColor = UIColor { traits in
            let base: UIColor = traits.userInterfaceStyle == .dark ? .white : .black
            return base.withAlphaComponent(0.16)
        }
        trackView.layer.cornerCurve = .continuous
        trackView.layer.borderWidth = 0.5
        trackView.layer.borderColor = UIColor.separator.cgColor
        trackView.clipsToBounds = true
        addSubview(trackView)

        thumbnailContainer.clipsToBounds = true
        trackView.addSubview(thumbnailContainer)

        selectionView.backgroundColor = .clear
        selectionView.layer.borderWidth = 1.5
        selectionView.layer.cornerCurve = .continuous
        selectionView.clipsToBounds = true
        selectionView.isUserInteractionEnabled = false
        addSubview(selectionView)

        selectedThumbnailView.backgroundColor = .tertiarySystemFill
        // Fill the fixed page-shaped frame by height, cropping unusually wide
        // pages at the sides instead of shrinking them inside the outline.
        selectedThumbnailView.contentMode = .scaleAspectFill
        selectedThumbnailView.clipsToBounds = true
        selectionView.addSubview(selectedThumbnailView)
        updateSelectionBorderColor()

        if #available(iOS 26.0, *) {
            previewContainer.effect = UIGlassEffect(style: .regular)
        } else {
            previewContainer.effect = UIBlurEffect(style: .systemMaterial)
        }
        previewContainer.layer.cornerCurve = .continuous
        previewContainer.layer.borderWidth = 0.5
        previewContainer.layer.borderColor = UIColor.separator.cgColor
        previewContainer.clipsToBounds = true
        previewContainer.isHidden = true
        previewContainer.isUserInteractionEnabled = false
        addSubview(previewContainer)

        previewImageView.contentMode = .scaleAspectFill
        previewImageView.clipsToBounds = true
        previewImageView.layer.cornerRadius = 16
        previewImageView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        previewContainer.contentView.addSubview(previewImageView)

        previewLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        previewLabel.textColor = .secondaryLabel
        previewLabel.textAlignment = .center
        previewLabel.backgroundColor = .clear
        previewLabel.layer.cornerRadius = 16
        previewLabel.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        previewLabel.clipsToBounds = true
        previewContainer.contentView.addSubview(previewLabel)
    }

    private func layoutThumbnailViews() {
        guard pageCount > 0, thumbnailContainer.bounds.width > 0 else { return }
        let contentFrame = thumbnailContentFrame
        let itemWidth = contentFrame.width / CGFloat(pageCount)

        for logicalIndex in 0..<pageCount {
            let visualIndex = direction == .forward ? logicalIndex : pageCount - logicalIndex - 1
            thumbnailViews[logicalIndex].frame = CGRect(
                x: contentFrame.minX + CGFloat(visualIndex) * itemWidth,
                y: 0,
                width: ceil(itemWidth) + 0.5,
                height: thumbnailContainer.bounds.height
            )
        }
        updateSelectionFrame(itemWidth: itemWidth)
    }

    private func updateValue(at location: CGPoint) {
        guard pageCount > 0, trackView.bounds.width > 0 else { return }
        let contentFrame = thumbnailContentFrame
        guard contentFrame.width > 0 else { return }
        let x = min(max(location.x - trackView.frame.minX, contentFrame.minX), contentFrame.maxX)
        let visualProgress = (x - contentFrame.minX) / contentFrame.width
        let logicalProgress = direction == .forward ? visualProgress : 1 - visualProgress
        currentValue = minimumValue + logicalProgress * (maximumValue - minimumValue)
    }

    private func updatePreviewPosition() {
        guard pageCount > 0, trackView.bounds.width > 0 else { return }
        let logicalIndex = pageIndex(for: currentValue)
        let visualIndex = direction == .forward ? logicalIndex : pageCount - logicalIndex - 1
        let contentFrame = thumbnailContentFrame
        let itemWidth = contentFrame.width / CGFloat(pageCount)
        updateSelectionFrame(itemWidth: itemWidth)

        let proposedCenterX = trackView.frame.minX + contentFrame.minX + (CGFloat(visualIndex) + 0.5) * itemWidth
        let halfWidth = Metrics.previewWidth / 2
        let centerX = min(max(proposedCenterX, halfWidth), bounds.width - halfWidth)
        previewContainer.center = CGPoint(
            x: centerX,
            y: trackView.frame.minY - Metrics.previewSpacing - previewContainer.bounds.height / 2
        )

        guard displayedPreviewIndex != logicalIndex else { return }
        displayedPreviewIndex = logicalIndex
        previewLabel.text = String(format: NSLocalizedString("PAGE_X"), logicalIndex + 1)
        previewImageView.image = closestLoadedThumbnail(to: logicalIndex)
        loadThumbnail(at: logicalIndex, prioritizePreview: true)
    }

    private func updateSelectionFrame(itemWidth: CGFloat) {
        guard pageCount > 0 else { return }
        let logicalIndex = pageIndex(for: currentValue)
        let visualIndex = direction == .forward ? logicalIndex : pageCount - logicalIndex - 1
        let height = Metrics.selectedPageHeight
        let width = height * Metrics.pageAspectRatio
        let contentFrame = thumbnailContentFrame
        selectionView.frame = CGRect(
            x: trackView.frame.minX + contentFrame.minX + (CGFloat(visualIndex) + 0.5) * itemWidth - width / 2,
            y: trackView.frame.midY - height / 2,
            width: width,
            height: height
        )
        selectedThumbnailView.frame = selectionView.bounds.insetBy(dx: 1.5, dy: 1.5)
        selectedThumbnailView.image = closestLoadedThumbnail(to: logicalIndex)
    }

    private var maximumThumbnailWidth: CGFloat {
        Metrics.trackHeight * Metrics.pageAspectRatio
    }

    /// Centers a run of fixed, page-proportioned thumbnail slots inside the
    /// track. This remains useful while constraints are settling or if the
    /// overlay has reached its maximum width.
    private var thumbnailContentFrame: CGRect {
        guard pageCount > 0 else { return .zero }
        let contentWidth = min(
            trackView.bounds.width,
            CGFloat(pageCount) * maximumThumbnailWidth
        )
        return CGRect(
            x: (trackView.bounds.width - contentWidth) / 2,
            y: 0,
            width: contentWidth,
            height: trackView.bounds.height
        )
    }

    private func pageIndex(for value: CGFloat) -> Int {
        guard pageCount > 1, maximumValue > minimumValue else { return 0 }
        let progress = (value - minimumValue) / (maximumValue - minimumValue)
        return min(max(Int(round(progress * CGFloat(pageCount - 1))), 0), pageCount - 1)
    }

    private func loadVisibleThumbnails() {
        let currentIndex = pageIndex(for: currentValue)
        let indexes = (0..<pageCount).sorted {
            abs($0 - currentIndex) < abs($1 - currentIndex)
        }
        for index in indexes {
            loadThumbnail(at: index)
        }
    }

    private func loadThumbnail(at index: Int, prioritizePreview: Bool = false) {
        guard loadedImages[index] == nil, !loadingIndexes.contains(index), let thumbnailProvider else { return }
        loadingIndexes.insert(index)
        let priority: TaskPriority = prioritizePreview ? .userInitiated : .utility
        let task = Task(priority: priority) { [weak self] in
            guard let self, !Task.isCancelled else { return }
            let image = await thumbnailProvider(index)
            await MainActor.run {
                self.loadingIndexes.remove(index)
                guard !Task.isCancelled, let image, index < self.thumbnailViews.count else { return }
                self.loadedImages[index] = image
                self.thumbnailViews[index].image = image
                let currentIndex = self.pageIndex(for: self.currentValue)
                self.selectedThumbnailView.image = self.closestLoadedThumbnail(to: currentIndex)
                if let displayedPreviewIndex = self.displayedPreviewIndex {
                    self.previewImageView.image = self.closestLoadedThumbnail(to: displayedPreviewIndex)
                }
            }
        }
        thumbnailTasks.append(task)
    }

    private func hidePreview() {
        UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState, .curveEaseIn]) {
            self.previewContainer.alpha = 0
        } completion: { _ in
            self.previewContainer.isHidden = true
            self.onPreviewVisibilityChange?(false)
        }
    }

    /// Transition/info pages can point just outside the chapter's real page
    /// range, and an exact thumbnail may still be loading. Keep the nearest
    /// real page visible rather than replacing the preview with an empty view.
    private func closestLoadedThumbnail(to index: Int) -> UIImage? {
        if let exactImage = loadedImages[index] {
            return exactImage
        }
        guard let closestIndex = loadedImages.keys.min(by: {
            abs($0 - index) < abs($1 - index)
        }) else {
            return nil
        }
        return loadedImages[closestIndex]
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            updateSelectionBorderColor()
        }
    }

    private func updateSelectionBorderColor() {
        let color = traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.95)
            : UIColor.black.withAlphaComponent(0.82)

        selectionView.layer.borderColor = color.cgColor
        selectionView.backgroundColor = color
        selectedThumbnailView.backgroundColor = color
    }
}
