//
//  ReaderThumbnailScrubberView.swift
//  Aidoku
//

import UIKit

/// An Apple Books-inspired page scrubber that keeps the reader's existing
/// normalized (0...1) progress API while presenting the chapter as thumbnails.
final class ReaderThumbnailScrubberView: UIControl {
    enum Direction {
        case forward
        case backward
    }

    enum ImageKind: Equatable {
        case strip
        case preview
    }

    private enum Metrics {
        static let horizontalInset: CGFloat = 22
        static let trackHeight: CGFloat = 22
        static let selectedPageHeight: CGFloat = 33
        static let activeSelectedPageHeight: CGFloat = 36
        static let pageAspectRatio: CGFloat = 0.70
        static let previewWidth: CGFloat = 82
        static let previewImageHeight: CGFloat = 108
        static let previewLabelHeight: CGFloat = 30
        static let previewSpacing: CGFloat = 12
        static let previewShowDelay: TimeInterval = 0.12
        static let selectionAnimationDuration: TimeInterval = 0.14
    }

    var direction: Direction = .forward {
        didSet {
            guard oldValue != direction else { return }
            layoutThumbnailViews()
            updatePreviewPosition()
        }
    }

    var minimumValue: CGFloat = 0
    var maximumValue: CGFloat = 1
    var onPreviewVisibilityChange: ((Bool) -> Void)?
    var usesContinuousProgress = false {
        didSet {
            guard oldValue != usesContinuousProgress else { return }
            if usesContinuousProgress {
                previewContainer.layer.removeAllAnimations()
                previewContainer.isHidden = true
                previewContainer.alpha = 0
                onPreviewVisibilityChange?(false)
            }
            updateAccessibilityValue()
            setNeedsLayout()
        }
    }
    var currentValue: CGFloat = 0 {
        didSet {
            let boundedValue = min(max(currentValue, minimumValue), maximumValue)
            if currentValue != boundedValue {
                currentValue = boundedValue
                return
            }
            if !usesContinuousProgress {
                layoutThumbnailViews()
            }
            updatePreviewPosition()
            updateAccessibilityValue()
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
    private var contentIdentifier: String?
    private var thumbnailViews: [UIImageView] = []
    private var previewTasks: [Int: Task<Void, Never>] = [:]
    private var previewShowWorkItem: DispatchWorkItem?
    private var thumbnailPreloadTask: Task<Void, Never>?
    private var isLoadingEnabled = false
    private var cachedThumbnailProvider: ((Int) async -> UIImage?)?
    private var thumbnailProvider: ((Int, ImageKind, @escaping @MainActor (UIImage) -> Void) async -> UIImage?)?
    private var loadedImages: [Int: UIImage] = [:]
    private var loadedPreviewImages: [Int: UIImage] = [:]
    private var displayedPreviewIndex: Int?
    private var loadGeneration = 0
    private var isActivelyScrubbing = false
    private var continuousPageIndex: Int?
    private var immediateGestureUpdatedValue = false
    private let selectionFeedbackGenerator = UISelectionFeedbackGenerator()

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
        previewShowWorkItem?.cancel()
        thumbnailPreloadTask?.cancel()
        previewTasks.values.forEach { $0.cancel() }
    }

    func configure(
        contentIdentifier: String,
        pageCount: Int,
        cachedThumbnailProvider: @escaping (Int) async -> UIImage?,
        thumbnailProvider: @escaping (Int, ImageKind, @escaping @MainActor (UIImage) -> Void) async -> UIImage?
    ) {
        let isSameContent = self.contentIdentifier == contentIdentifier && self.pageCount == pageCount
        self.contentIdentifier = contentIdentifier
        self.pageCount = pageCount
        self.cachedThumbnailProvider = cachedThumbnailProvider
        self.thumbnailProvider = thumbnailProvider

        if isSameContent {
            if isLoadingEnabled {
                loadVisibleThumbnails()
            }
            return
        }

        resetLoadedContent(clearViews: true)
        thumbnailViews.forEach { $0.removeFromSuperview() }
        thumbnailViews.removeAll()

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
        if isLoadingEnabled {
            loadVisibleThumbnails()
        }
    }

    func setLoadingEnabled(_ enabled: Bool) {
        guard enabled != isLoadingEnabled else { return }
        isLoadingEnabled = enabled
        if enabled {
            loadVisibleThumbnails()
        } else {
            pauseLoading()
        }
    }

    func move(toValue value: CGFloat) {
        currentValue = value
    }

    func setCurrentPage(_ page: Int) {
        guard pageCount > 0 else { return }
        let index = min(max(page - 1, 0), pageCount - 1)
        guard continuousPageIndex != index else { return }
        continuousPageIndex = index
        if usesContinuousProgress {
            updatePreviewPosition()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let trackWidth = max(0, bounds.width - Metrics.horizontalInset * 2)
        let borderWidth = 1 / max(traitCollection.displayScale, 1)
        trackView.frame = pixelAligned(CGRect(
            x: Metrics.horizontalInset,
            y: (bounds.height - Metrics.trackHeight) / 2 - 0.125,
            width: trackWidth,
            height: Metrics.trackHeight
        ))
        thumbnailContainer.frame = trackView.bounds
        trackView.layer.cornerRadius = 0
        trackView.layer.borderWidth = borderWidth
        trackView.layer.borderColor = Self.activePageBorderColor.cgColor
        selectionView.layer.cornerRadius = 0
        selectionView.layer.borderWidth = borderWidth
        selectionView.layer.borderColor = Self.activePageBorderColor.cgColor
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
        immediateGestureUpdatedValue = false
        let location = touch.location(in: self)
        let beganOnSelection = selectionView.frame.insetBy(dx: -8, dy: -8).contains(location)
        beginActiveInteraction(producesFeedback: beganOnSelection)
        if !usesContinuousProgress {
            schedulePreviewShow()
        }
        updateValue(at: location)
        sendActions(for: .valueChanged)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateValue(at: touch.location(in: self))
        sendActions(for: .valueChanged)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        setSelectionExpanded(false)
        if !usesContinuousProgress {
            hidePreview()
        }
        sendActions(for: .editingDidEnd)
    }

    override func cancelTracking(with event: UIEvent?) {
        setSelectionExpanded(false)
        if !usesContinuousProgress {
            hidePreview()
        }
        sendActions(for: .editingDidEnd)
    }

    override func accessibilityIncrement() {
        guard usesContinuousProgress else { return }
        adjustAccessibilityValue(by: 0.05)
    }

    override func accessibilityDecrement() {
        guard usesContinuousProgress else { return }
        adjustAccessibilityValue(by: -0.05)
    }

    private func configure() {
        clipsToBounds = false
        isExclusiveTouch = true

        // A Webtoon reader's scroll view delays UIControl tracking until the
        // finger moves. This zero-delay, non-cancelling recognizer lets the
        // active thumbnail respond immediately without taking over dragging.
        let immediateTouchRecognizer = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleImmediateTouch(_:))
        )
        immediateTouchRecognizer.minimumPressDuration = 0
        immediateTouchRecognizer.allowableMovement = .greatestFiniteMagnitude
        immediateTouchRecognizer.cancelsTouchesInView = false
        immediateTouchRecognizer.delaysTouchesBegan = false
        immediateTouchRecognizer.delegate = self
        addGestureRecognizer(immediateTouchRecognizer)

        trackView.backgroundColor = UIColor { traits in
            let base: UIColor = traits.userInterfaceStyle == .dark ? .white : .black
            return base.withAlphaComponent(0.16)
        }
        trackView.layer.cornerCurve = .continuous
        trackView.clipsToBounds = true
        addSubview(trackView)

        thumbnailContainer.clipsToBounds = true
        trackView.addSubview(thumbnailContainer)

        selectionView.backgroundColor = .clear
        selectionView.layer.cornerCurve = .continuous
        selectionView.clipsToBounds = true
        selectionView.isUserInteractionEnabled = false
        addSubview(selectionView)

        selectedThumbnailView.backgroundColor = Self.loadingPlaceholderColor
        // Fill the fixed page-shaped frame by height, cropping unusually wide
        // pages at the sides instead of shrinking them inside the outline.
        selectedThumbnailView.contentMode = .scaleAspectFill
        selectedThumbnailView.clipsToBounds = true
        selectionView.addSubview(selectedThumbnailView)
        setContrastColor(.label)

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
        if usesContinuousProgress {
            layoutStaticThumbnailViews(in: contentFrame)
            updateSelectionFrame()
            return
        }

        let activeLogicalIndex = pageIndex(for: currentValue)
        let activeVisualIndex = direction == .forward
            ? activeLogicalIndex
            : pageCount - activeLogicalIndex - 1
        let activeWidth = Metrics.selectedPageHeight * Metrics.pageAspectRatio
        let fittedActiveWidth = min(activeWidth, contentFrame.width)
        let otherWidth = pageCount > 1
            ? max(0, (contentFrame.width - fittedActiveWidth) / CGFloat(pageCount - 1))
            : fittedActiveWidth
        var x = contentFrame.minX

        for visualIndex in 0..<pageCount {
            let logicalIndex = direction == .forward
                ? visualIndex
                : pageCount - visualIndex - 1
            let width = visualIndex == activeVisualIndex ? fittedActiveWidth : otherWidth
            thumbnailViews[logicalIndex].frame = CGRect(
                x: x,
                y: 0,
                width: width,
                height: thumbnailContainer.bounds.height
            )
            x += width
        }
        updateSelectionFrame()
    }

    /// Webtoon progress moves continuously rather than selecting one discrete
    /// thumbnail at a time. Keep the strip itself stable so crossing a page
    /// boundary only changes the moving selection overlay and its image.
    private func layoutStaticThumbnailViews(in contentFrame: CGRect) {
        let thumbnailWidth = contentFrame.width / CGFloat(pageCount)
        for visualIndex in 0..<pageCount {
            let logicalIndex = direction == .forward
                ? visualIndex
                : pageCount - visualIndex - 1
            thumbnailViews[logicalIndex].frame = CGRect(
                x: contentFrame.minX + CGFloat(visualIndex) * thumbnailWidth,
                y: 0,
                width: thumbnailWidth,
                height: thumbnailContainer.bounds.height
            )
        }
    }

    private func updateValue(at location: CGPoint) {
        guard pageCount > 0, trackView.bounds.width > 0 else { return }
        let contentFrame = thumbnailContentFrame
        guard contentFrame.width > 0 else { return }
        let x = min(max(location.x - trackView.frame.minX, contentFrame.minX), contentFrame.maxX)
        if usesContinuousProgress {
            var progress = (x - contentFrame.minX) / contentFrame.width
            if direction == .backward {
                progress = 1 - progress
            }
            currentValue = minimumValue + progress * (maximumValue - minimumValue)
            return
        }
        let logicalIndex = (0..<pageCount).min { lhs, rhs in
            abs(thumbnailViews[lhs].frame.midX - x) < abs(thumbnailViews[rhs].frame.midX - x)
        } ?? 0
        let logicalProgress = CGFloat(logicalIndex) / CGFloat(max(pageCount - 1, 1))
        currentValue = minimumValue + logicalProgress * (maximumValue - minimumValue)
    }

    private func updatePreviewPosition() {
        guard pageCount > 0, trackView.bounds.width > 0 else { return }
        let logicalIndex = pageIndex(for: currentValue)
        updateSelectionFrame()

        let proposedCenterX = selectionView.center.x
        previewContainer.center = CGPoint(
            x: proposedCenterX,
            y: selectionView.frame.minY - Metrics.previewSpacing - previewContainer.bounds.height / 2
        )

        guard displayedPreviewIndex != logicalIndex else { return }
        displayedPreviewIndex = logicalIndex
        previewLabel.text = String(format: NSLocalizedString("PAGE_X"), logicalIndex + 1)
        previewImageView.image = loadedPreviewImages[logicalIndex]
            ?? loadedImages[logicalIndex]
        prefetchPreviewImages(around: logicalIndex)
    }

    private func updateSelectionFrame() {
        guard pageCount > 0 else { return }
        let logicalIndex = pageIndex(for: currentValue)
        let height = isActivelyScrubbing
            ? Metrics.activeSelectedPageHeight
            : Metrics.selectedPageHeight
        let width = height * Metrics.pageAspectRatio
        let proposedCenterX: CGFloat
        if usesContinuousProgress, maximumValue > minimumValue {
            var progress = (currentValue - minimumValue) / (maximumValue - minimumValue)
            if direction == .backward {
                progress = 1 - progress
            }
            let contentFrame = thumbnailContentFrame
            proposedCenterX = trackView.frame.minX + contentFrame.minX + contentFrame.width * progress
        } else {
            let activeFrame = thumbnailViews[logicalIndex].frame
            proposedCenterX = trackView.frame.minX + activeFrame.midX
        }
        let centerX = min(
            max(proposedCenterX, trackView.frame.minX + width / 2),
            trackView.frame.maxX - width / 2
        )
        selectionView.frame = pixelAligned(CGRect(
            x: centerX - width / 2,
            y: trackView.frame.midY - height / 2,
            width: width,
            height: height
        ))
        selectedThumbnailView.frame = selectionView.bounds
        selectedThumbnailView.image = selectedImage(for: logicalIndex)
    }

    private func setSelectionExpanded(_ expanded: Bool) {
        guard isActivelyScrubbing != expanded else { return }
        isActivelyScrubbing = expanded
        UIView.animate(
            withDuration: Metrics.selectionAnimationDuration,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]
        ) {
            self.updatePreviewPosition()
        }
    }

    private func beginActiveInteraction(producesFeedback: Bool) {
        guard !isActivelyScrubbing else { return }
        if producesFeedback {
            selectionFeedbackGenerator.prepare()
        }
        setSelectionExpanded(true)
        if producesFeedback {
            selectionFeedbackGenerator.selectionChanged()
        }
    }

    @objc private func handleImmediateTouch(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
            case .began:
                let location = recognizer.location(in: self)
                if usesContinuousProgress {
                    immediateGestureUpdatedValue = true
                    beginActiveInteraction(producesFeedback: true)
                    updateValue(at: location)
                    sendActions(for: .valueChanged)
                } else if selectionView.frame.insetBy(dx: -8, dy: -8).contains(location) {
                    beginActiveInteraction(producesFeedback: true)
                }
            case .ended, .cancelled, .failed:
                let shouldFinishValueChange = immediateGestureUpdatedValue && !isTracking
                immediateGestureUpdatedValue = false
                if !isTracking {
                    setSelectionExpanded(false)
                }
                if shouldFinishValueChange {
                    sendActions(for: .editingDidEnd)
                }
            default:
                break
        }
    }

    private var maximumThumbnailWidth: CGFloat {
        Metrics.trackHeight * Metrics.pageAspectRatio
    }

    private func pixelAligned(_ rect: CGRect) -> CGRect {
        let scale = max(traitCollection.displayScale, 1)
        func aligned(_ value: CGFloat) -> CGFloat {
            round(value * scale) / scale
        }
        return CGRect(
            x: aligned(rect.origin.x),
            y: aligned(rect.origin.y),
            width: aligned(rect.width),
            height: aligned(rect.height)
        )
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
        if usesContinuousProgress, let continuousPageIndex {
            return min(max(continuousPageIndex, 0), max(pageCount - 1, 0))
        }
        guard pageCount > 1, maximumValue > minimumValue else { return 0 }
        let progress = (value - minimumValue) / (maximumValue - minimumValue)
        return min(max(Int(round(progress * CGFloat(pageCount - 1))), 0), pageCount - 1)
    }

    private func adjustAccessibilityValue(by amount: CGFloat) {
        let range = maximumValue - minimumValue
        guard range > 0 else { return }
        let progress = (currentValue - minimumValue) / range
        let steppedProgress = amount > 0
            ? min(1, floor(progress * 20 + 1) / 20)
            : max(0, ceil(progress * 20 - 1) / 20)
        currentValue = minimumValue + steppedProgress * range
        sendActions(for: .valueChanged)
        sendActions(for: .editingDidEnd)
    }

    private func updateAccessibilityValue() {
        guard usesContinuousProgress, maximumValue > minimumValue else { return }
        let progress = (currentValue - minimumValue) / (maximumValue - minimumValue)
        accessibilityValue = "\(Int((progress * 100).rounded())) percent"
    }

    private func loadVisibleThumbnails() {
        guard isLoadingEnabled, pageCount > 0 else { return }
        let currentIndex = pageIndex(for: currentValue)
        let indexes = (0..<pageCount).sorted {
            abs($0 - currentIndex) < abs($1 - currentIndex)
        }
        thumbnailPreloadTask?.cancel()
        let generation = loadGeneration
        thumbnailPreloadTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }

            // First fill every persistent cache hit. Cache misses return
            // immediately and never wait behind a network request.
            if let cachedThumbnailProvider = self.cachedThumbnailProvider {
                for index in indexes where self.loadedImages[index] == nil {
                    guard !Task.isCancelled, self.isLoadingEnabled,
                          self.loadGeneration == generation else { return }
                    if let image = await cachedThumbnailProvider(index) {
                        self.applyThumbnail(image, at: index, generation: generation)
                    }
                    await Task.yield()
                }
            }

            // Give the real reader page first access to the network. This also
            // avoids downloading an entire chapter when controls are only
            // shown very briefly.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, self.isLoadingEnabled,
                  self.loadGeneration == generation else { return }
            self.prefetchPreviewImages(around: currentIndex)

            let missingIndexes = indexes.filter { self.loadedImages[$0] == nil }
            for batchStart in stride(from: 0, to: missingIndexes.count, by: 3) {
                guard !Task.isCancelled, self.isLoadingEnabled,
                      self.loadGeneration == generation else { return }
                let batchEnd = min(batchStart + 3, missingIndexes.count)
                await withTaskGroup(of: Void.self) { group in
                    for index in missingIndexes[batchStart..<batchEnd] {
                        group.addTask { [weak self] in
                            await self?.fetchThumbnail(at: index, generation: generation)
                        }
                    }
                    await group.waitForAll()
                }
            }
            guard self.loadGeneration == generation else { return }
            self.thumbnailPreloadTask = nil
        }
    }

    private func applyThumbnail(_ image: UIImage, at index: Int, generation: Int) {
        guard isLoadingEnabled, loadGeneration == generation,
              index < thumbnailViews.count else { return }
        loadedImages[index] = image
        thumbnailViews[index].image = image
        let currentIndex = pageIndex(for: currentValue)
        selectedThumbnailView.image = selectedImage(for: currentIndex)
        if let displayedPreviewIndex {
            previewImageView.image = loadedPreviewImages[displayedPreviewIndex]
                ?? loadedImages[displayedPreviewIndex]
        }
    }

    private func fetchThumbnail(at index: Int, generation: Int) async {
        guard isLoadingEnabled,
              loadedImages[index] == nil,
              let thumbnailProvider else { return }
        let image = await thumbnailProvider(index, .strip) { [weak self] intermediateImage in
            guard let self,
                  self.isLoadingEnabled,
                  self.loadGeneration == generation,
                  index < self.thumbnailViews.count else { return }
            self.loadedImages[index] = intermediateImage
            self.thumbnailViews[index].image = intermediateImage
        }
        guard !Task.isCancelled, isLoadingEnabled, loadGeneration == generation,
              let image, index < thumbnailViews.count else { return }
        applyThumbnail(image, at: index, generation: generation)
    }

    private func prefetchPreviewImages(around index: Int) {
        guard isLoadingEnabled, pageCount > 0 else { return }
        // The current page is the only high-resolution image needed while the
        // controls are idle. Adjacent previews are prepared only while the
        // user is actively scrubbing, avoiding two full-page downloads every
        // time the toolbar appears.
        let candidateIndexes = isTracking && !usesContinuousProgress
            ? [index, index - 1, index + 1]
            : [index]
        let nearbyIndexes = candidateIndexes
            .filter { $0 >= 0 && $0 < pageCount }
        let retainedIndexes = Set(nearbyIndexes)
        loadedPreviewImages = loadedPreviewImages.filter { retainedIndexes.contains($0.key) }
        let obsoleteTaskIndexes = previewTasks.keys.filter { !retainedIndexes.contains($0) }
        for taskIndex in obsoleteTaskIndexes {
            previewTasks[taskIndex]?.cancel()
            previewTasks[taskIndex] = nil
        }
        nearbyIndexes.forEach(loadPreviewThumbnail)
    }

    private func loadPreviewThumbnail(at index: Int) {
        guard loadedPreviewImages[index] == nil, previewTasks[index] == nil,
              let thumbnailProvider else { return }
        let generation = loadGeneration
        previewTasks[index] = Task(priority: .userInitiated) { [weak self] in
            let image = await thumbnailProvider(index, .preview) { _ in }
            guard let self else { return }
            self.previewTasks[index] = nil
            guard !Task.isCancelled, self.isLoadingEnabled,
                  self.loadGeneration == generation, let image else { return }
            self.loadedPreviewImages[index] = image
            if self.pageIndex(for: self.currentValue) == index {
                self.selectedThumbnailView.image = image
            }
            if self.displayedPreviewIndex == index {
                self.previewImageView.image = image
            }
        }
    }

    private func resetLoadedContent(clearViews: Bool) {
        loadGeneration &+= 1
        thumbnailPreloadTask?.cancel()
        thumbnailPreloadTask = nil
        previewTasks.values.forEach { $0.cancel() }
        previewTasks.removeAll()
        loadedImages.removeAll()
        loadedPreviewImages.removeAll()
        displayedPreviewIndex = nil
        previewImageView.image = nil
        selectedThumbnailView.image = nil
        if clearViews {
            thumbnailViews.forEach { $0.image = nil }
        }
    }

    private func pauseLoading() {
        loadGeneration &+= 1
        thumbnailPreloadTask?.cancel()
        thumbnailPreloadTask = nil
        previewTasks.values.forEach { $0.cancel() }
        previewTasks.removeAll()
    }

    private func hidePreview() {
        previewShowWorkItem?.cancel()
        previewShowWorkItem = nil
        previewContainer.layer.removeAllAnimations()
        previewContainer.alpha = 0
        previewContainer.isHidden = true
        onPreviewVisibilityChange?(false)
    }

    private func schedulePreviewShow() {
        previewShowWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.usesContinuousProgress, self.isTracking else { return }
            self.previewContainer.isHidden = false
            self.previewContainer.alpha = 1
            self.onPreviewVisibilityChange?(true)
        }
        previewShowWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Metrics.previewShowDelay,
            execute: workItem
        )
    }

    private func selectedImage(for index: Int) -> UIImage? {
        loadedPreviewImages[index]
            ?? loadedImages[index]
    }

    func setContrastColor(_ color: UIColor) {
        selectionView.layer.borderColor = Self.activePageBorderColor.cgColor
        selectionView.backgroundColor = .clear
        selectedThumbnailView.backgroundColor = Self.loadingPlaceholderColor
    }

    private static let loadingPlaceholderColor = UIColor.systemGray.withAlphaComponent(0.35)
    private static let activePageBorderColor = UIColor.systemGray.withAlphaComponent(0.6)

    func setOverlayAppearance(_ style: UIUserInterfaceStyle) {
        previewContainer.overrideUserInterfaceStyle = style
    }
}

extension ReaderThumbnailScrubberView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
