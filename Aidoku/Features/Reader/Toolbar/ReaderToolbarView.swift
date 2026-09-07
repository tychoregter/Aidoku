//
//  ReaderToolbarView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import Combine
import UIKit

class ReaderToolbarView: UIView {
    private static let minimumPageLabelWidth: CGFloat = 46
    private static let maximumPageLabelWidth: CGFloat = 88
    private static let pageLabelWidthPadding: CGFloat = 4

    private static let timestampColor = UIColor.secondaryLabel

    var currentPageValue: Int? {
        didSet {
            if oldValue != currentPageValue {
                let feedbackGenerator = UISelectionFeedbackGenerator()
                feedbackGenerator.selectionChanged()
            }
        }
    }
    var currentPage: Int? {
        didSet { updatePageLabels() }
    }
    var totalPages: Int? {
        didSet { updatePageLabels() }
    }

    let sliderView = ReaderSliderView()
    let thumbnailScrubberView = ReaderThumbnailScrubberView()
    var onScrubberStyleChange: ((Bool) -> Void)?
    var onThumbnailScrubberPreferredWidthChange: ((CGFloat?) -> Void)?
    private(set) var usesThumbnailScrubber = false
    private let incognitoModeLabel = UILabel()
    private let currentPageLabel = UILabel()
    let thumbnailPageCounterView = UIVisualEffectView()
    private let thumbnailPageCounterLabel = UILabel()
    private var currentPageLabelWidthConstraint: NSLayoutConstraint?
    private var thumbnailPageCounterPositionConstraints: [NSLayoutConstraint] = []
    private var supportsThumbnailScrubber = false

    private var cancellables: [AnyCancellable] = []

    init() {
        super.init(frame: .zero)
        configure()
        constrain()
        observe()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        incognitoModeLabel.font = .systemFont(ofSize: 10)
        incognitoModeLabel.textColor = .secondaryLabel
        incognitoModeLabel.textAlignment = .left
        incognitoModeLabel.isHidden = !AppSettings.general.incognitoMode.get()
        addSubview(incognitoModeLabel)

        currentPageLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        currentPageLabel.textColor = Self.timestampColor
        currentPageLabel.textAlignment = .right
        currentPageLabel.adjustsFontSizeToFitWidth = true
        currentPageLabel.minimumScaleFactor = 0.8
        currentPageLabel.setContentHuggingPriority(.required, for: .horizontal)
        currentPageLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(currentPageLabel)

        sliderView.semanticContentAttribute = .playback // for rtl languages
        addSubview(sliderView)
        thumbnailScrubberView.semanticContentAttribute = .playback
        thumbnailScrubberView.isHidden = true
        thumbnailScrubberView.onPreviewVisibilityChange = { [weak self] isVisible in
            guard let self else { return }
            if isVisible {
                self.bringSubviewToFront(self.thumbnailScrubberView)
            } else {
                self.thumbnailPageCounterView.superview?.bringSubviewToFront(self.thumbnailPageCounterView)
            }
        }
        addSubview(thumbnailScrubberView)

        if #available(iOS 26.0, *) {
            thumbnailPageCounterView.effect = UIGlassEffect(style: .regular)
        } else {
            thumbnailPageCounterView.effect = UIBlurEffect(style: .systemMaterial)
        }
        thumbnailPageCounterView.layer.cornerRadius = 10
        thumbnailPageCounterView.layer.cornerCurve = .continuous
        thumbnailPageCounterView.clipsToBounds = true
        thumbnailPageCounterView.isUserInteractionEnabled = false
        thumbnailPageCounterView.isHidden = true
        addSubview(thumbnailPageCounterView)

        thumbnailPageCounterLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        thumbnailPageCounterLabel.textColor = .secondaryLabel
        thumbnailPageCounterLabel.textAlignment = .center
        thumbnailPageCounterView.contentView.addSubview(thumbnailPageCounterLabel)
        bringSubviewToFront(incognitoModeLabel)
        bringSubviewToFront(currentPageLabel)
    }

    func constrain() {
        incognitoModeLabel.translatesAutoresizingMaskIntoConstraints = false
        currentPageLabel.translatesAutoresizingMaskIntoConstraints = false
        sliderView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailScrubberView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailPageCounterView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailPageCounterLabel.translatesAutoresizingMaskIntoConstraints = false

        let currentPageLabelWidthConstraint = currentPageLabel.widthAnchor.constraint(
            equalToConstant: Self.minimumPageLabelWidth
        )
        self.currentPageLabelWidthConstraint = currentPageLabelWidthConstraint

        thumbnailPageCounterPositionConstraints = [
            thumbnailPageCounterView.centerXAnchor.constraint(equalTo: centerXAnchor),
            thumbnailPageCounterView.bottomAnchor.constraint(equalTo: topAnchor, constant: -10)
        ]

        NSLayoutConstraint.activate([
            incognitoModeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            incognitoModeLabel.centerYAnchor.constraint(equalTo: sliderView.centerYAnchor),

            currentPageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            currentPageLabelWidthConstraint,
            currentPageLabel.centerYAnchor.constraint(equalTo: sliderView.centerYAnchor),

            sliderView.heightAnchor.constraint(equalTo: heightAnchor),
            sliderView.centerYAnchor.constraint(equalTo: centerYAnchor),
            sliderView.leadingAnchor.constraint(equalTo: currentPageLabel.trailingAnchor, constant: 8),
            sliderView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            thumbnailScrubberView.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumbnailScrubberView.trailingAnchor.constraint(equalTo: trailingAnchor),
            thumbnailScrubberView.topAnchor.constraint(equalTo: topAnchor),
            thumbnailScrubberView.bottomAnchor.constraint(equalTo: bottomAnchor),

            thumbnailPageCounterView.heightAnchor.constraint(equalToConstant: 34),
            thumbnailPageCounterView.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
            thumbnailPageCounterLabel.leadingAnchor.constraint(equalTo: thumbnailPageCounterView.contentView.leadingAnchor, constant: 12),
            thumbnailPageCounterLabel.trailingAnchor.constraint(equalTo: thumbnailPageCounterView.contentView.trailingAnchor, constant: -12),
            thumbnailPageCounterLabel.topAnchor.constraint(equalTo: thumbnailPageCounterView.contentView.topAnchor),
            thumbnailPageCounterLabel.bottomAnchor.constraint(equalTo: thumbnailPageCounterView.contentView.bottomAnchor)
        ] + thumbnailPageCounterPositionConstraints)
    }

    /// Places the counter inside the same glass container as the reader bar.
    /// Keeping its positional constraints here also makes this easy to reverse.
    func moveThumbnailPageCounter(
        to container: UIView,
        centeredOn centerXAnchor: NSLayoutXAxisAnchor,
        above topAnchor: NSLayoutYAxisAnchor
    ) {
        NSLayoutConstraint.deactivate(thumbnailPageCounterPositionConstraints)
        thumbnailPageCounterView.removeFromSuperview()
        container.addSubview(thumbnailPageCounterView)
        thumbnailPageCounterPositionConstraints = [
            thumbnailPageCounterView.centerXAnchor.constraint(equalTo: centerXAnchor),
            thumbnailPageCounterView.bottomAnchor.constraint(equalTo: topAnchor, constant: -10)
        ]
        NSLayoutConstraint.activate(thumbnailPageCounterPositionConstraints)
    }

    func observe() {
        NotificationCenter.default.publisher(for: .init(AppSettings.general.incognitoMode.key))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshScrubberStyle()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .init(AppSettings.reader.thumbnailScrubber.key))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshScrubberStyle()
            }
            .store(in: &cancellables)
    }

    // allow slider thumb to be touched outside bounds
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let activeControl: UIControl = thumbnailScrubberView.isHidden ? sliderView : thumbnailScrubberView
        if activeControl.bounds.contains(convert(point, to: activeControl)) {
            return activeControl
        }
        return super.hitTest(point, with: event)
    }

    func displayPage(_ page: Int) {
        guard let totalPages = totalPages else {
            return
        }
        let boundedPage = min(max(page, 1), totalPages)
        updatePageLabel(page: boundedPage, totalPages: totalPages)
        currentPageValue = boundedPage
        let value = CGFloat(boundedPage - 1) / max(CGFloat(totalPages - 1), 1)
        sliderView.move(toValue: value)
        thumbnailScrubberView.move(toValue: value)
        thumbnailScrubberView.accessibilityValue = "\(boundedPage) of \(totalPages)"
        thumbnailPageCounterLabel.text = "\(boundedPage) of \(totalPages)"
    }

    func setProgressContrastColor(_ color: UIColor) {
        UIView.animate(
            withDuration: 0.14,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]
        ) {
            self.currentPageLabel.textColor = color.withAlphaComponent(0.50)
            self.sliderView.setContrastColor(color)
            self.thumbnailScrubberView.setContrastColor(color)
        }
    }

    func setProgressOverlayAppearance(isDark: Bool) {
        let style: UIUserInterfaceStyle = isDark ? .dark : .light
        thumbnailPageCounterView.overrideUserInterfaceStyle = style
        thumbnailScrubberView.setOverlayAppearance(style)
    }

    func updatePageLabels() {
        guard let currentPage, let totalPages else {
            currentPageLabel.text = nil
            return
        }

        updatePageLabel(page: min(max(currentPage, 1), totalPages), totalPages: totalPages)
        incognitoModeLabel.text = NSLocalizedString("INCOGNITO_MODE")
    }

    private func updatePageLabel(page: Int, totalPages: Int) {
        currentPageLabel.text = "\(page) / \(totalPages)"
        thumbnailPageCounterLabel.text = "\(page) of \(totalPages)"

        // Reserve enough room for the widest value this title can display so
        // advancing between pages never shifts the progress bar.
        let maximumText = "\(totalPages) / \(totalPages)" as NSString
        let measuredWidth = ceil(maximumText.size(withAttributes: [.font: currentPageLabel.font as Any]).width)
            + Self.pageLabelWidthPadding
        currentPageLabelWidthConstraint?.constant = min(
            max(measuredWidth, Self.minimumPageLabelWidth),
            Self.maximumPageLabelWidth
        )
    }

    func updateSliderPosition() {
        guard let currentPage = currentPage, let totalPages = totalPages else { return }
        moveSlider(to: CGFloat(currentPage - 1) / max(CGFloat(totalPages - 1), 1))
    }

    func setSliderDirection(_ direction: ReaderSliderView.SliderDirection) {
        sliderView.direction = direction
        thumbnailScrubberView.direction = direction
    }

    func moveSlider(to value: CGFloat) {
        sliderView.move(toValue: value)
        thumbnailScrubberView.move(toValue: value)
    }

    func configureThumbnails(
        pageCount: Int,
        supportsThumbnails: Bool,
        provider: @escaping (Int) async -> UIImage?
    ) {
        supportsThumbnailScrubber = supportsThumbnails
        thumbnailScrubberView.configure(pageCount: pageCount, thumbnailProvider: provider)
        onThumbnailScrubberPreferredWidthChange?(thumbnailScrubberView.preferredWidth)
        thumbnailScrubberView.accessibilityValue = "\(currentPage ?? 1) of \(pageCount)"
        thumbnailScrubberView.isAccessibilityElement = true
        thumbnailScrubberView.accessibilityTraits = .adjustable
        refreshScrubberStyle()
    }

    private func refreshScrubberStyle() {
        let usesThumbnails = AppSettings.reader.thumbnailScrubber.get()
            && supportsThumbnailScrubber
        let styleChanged = usesThumbnails != usesThumbnailScrubber
        usesThumbnailScrubber = usesThumbnails
        thumbnailScrubberView.isHidden = !usesThumbnails
        thumbnailScrubberView.setLoadingEnabled(usesThumbnails)
        thumbnailPageCounterView.isHidden = !usesThumbnails
        sliderView.isHidden = usesThumbnails
        currentPageLabel.isHidden = usesThumbnails
        incognitoModeLabel.isHidden = usesThumbnails || !AppSettings.general.incognitoMode.get()
        if styleChanged {
            onScrubberStyleChange?(usesThumbnails)
        }
        if usesThumbnails {
            onThumbnailScrubberPreferredWidthChange?(thumbnailScrubberView.preferredWidth)
        }
    }
}
