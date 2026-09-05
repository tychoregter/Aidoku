//
//  ReaderSliderView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/20/22.
//

import UIKit

class ReaderSliderView: UIControl {
    private enum Metrics {
        static let restingTrackHeight: CGFloat = 8
        static let activeTrackHeight: CGFloat = 16
        static let horizontalInset: CGFloat = 5
        static let animationDuration: TimeInterval = 0.2
    }

    enum SliderDirection {
        case forward
        case backward
    }

    var direction: SliderDirection = .forward {
        didSet {
            trackPositionConstraint?.isActive = false
            if direction == .forward {
                trackPositionConstraint = progressedTrackView.leadingAnchor.constraint(equalTo: trackView.leadingAnchor)
            } else {
                trackPositionConstraint = progressedTrackView.trailingAnchor.constraint(equalTo: trackView.trailingAnchor)
            }
            trackPositionConstraint?.isActive = true
        }
    }

    var minimumValue: CGFloat = 0
    var maximumValue: CGFloat = 1
    var currentValue: CGFloat = 0 {
        didSet {
            let boundedValue = boundValue(
                currentValue,
                toLowerValue: minimumValue,
                upperValue: maximumValue
            )
            if currentValue != boundedValue {
                currentValue = boundedValue
                return
            }
            updateLayerFrames()
        }
    }

    private lazy var trackView = {
        let trackView: UIView
        if #available(iOS 26.0, *) {
            let glassTrack = LiquidLensView(frame: .zero)
            glassTrack.restingBackgroundColor = .systemGray4
            trackView = glassTrack
        } else {
            let fallbackTrack = UIView()
            fallbackTrack.backgroundColor = .systemGray3
            trackView = fallbackTrack
        }
        trackView.layer.cornerRadius = 4
        trackView.layer.cornerCurve = .continuous
        trackView.clipsToBounds = true
        trackView.isUserInteractionEnabled = true
        return trackView
    }()
    private lazy var progressedTrackView = {
        let progressedTrackView = UIView()
        progressedTrackView.backgroundColor = .label
        progressedTrackView.isUserInteractionEnabled = true
        return progressedTrackView
    }()

    private var trackWidthConstraint: NSLayoutConstraint?
    private var trackPositionConstraint: NSLayoutConstraint?
    private var trackHeightConstraint: NSLayoutConstraint?
    private var progressedTrackHeightConstraint: NSLayoutConstraint?

    private var previousLocation = CGPoint()
    private var isScrubbing = false

    override var frame: CGRect {
        didSet {
            updateLayerFrames()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        addSubview(trackView)
        trackView.addSubview(progressedTrackView)
    }

    func constrain() {
        trackView.translatesAutoresizingMaskIntoConstraints = false
        progressedTrackView.translatesAutoresizingMaskIntoConstraints = false

        trackWidthConstraint = progressedTrackView.widthAnchor.constraint(equalToConstant: 5)
        trackWidthConstraint?.isActive = true
        trackPositionConstraint = progressedTrackView.leadingAnchor.constraint(equalTo: trackView.leadingAnchor)
        trackPositionConstraint?.isActive = true
        trackHeightConstraint = trackView.heightAnchor.constraint(equalToConstant: Metrics.restingTrackHeight)
        progressedTrackHeightConstraint = progressedTrackView.heightAnchor.constraint(
            equalToConstant: Metrics.restingTrackHeight
        )

        NSLayoutConstraint.activate([
            trackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalInset),
            trackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalInset),
            trackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            trackHeightConstraint!,

            progressedTrackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            progressedTrackHeightConstraint!
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayerFrames()
        trackView.layer.cornerRadius = trackView.bounds.height / 2
    }

    private func updateLayerFrames() {
        guard trackView.frame.size != .zero else { return }
        let position = positionForValue(currentValue)
        let trackWidth = trackView.bounds.width
        if direction == .forward {
            let rawProgressWidth = position
            let progressWidth = min(trackWidth, max(0, rawProgressWidth))
            trackWidthConstraint?.constant = progressWidth
        } else {
            let rawProgressWidth = trackView.bounds.width - position
            let progressWidth = min(trackWidth, max(0, rawProgressWidth))
            trackWidthConstraint?.constant = progressWidth
        }
    }
}

extension ReaderSliderView {
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        previousLocation = touch.location(in: self)

        isScrubbing = true
        UIView.animate(withDuration: Metrics.animationDuration) {
            self.trackHeightConstraint?.constant = Metrics.activeTrackHeight
            self.progressedTrackHeightConstraint?.constant = Metrics.activeTrackHeight
            self.layoutIfNeeded()
        }
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let location = touch.location(in: self)

        let deltaLocation = location.x - previousLocation.x
        let deltaValue = (maximumValue - minimumValue) * deltaLocation / bounds.width

        previousLocation = location

        if isScrubbing {
            if direction == .forward {
                currentValue += deltaValue
            } else {
                currentValue -= deltaValue
            }
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        updateLayerFrames()

        CATransaction.commit()

        sendActions(for: .valueChanged)

        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        isScrubbing = false
        UIView.animate(withDuration: Metrics.animationDuration) {
            self.trackHeightConstraint?.constant = Metrics.restingTrackHeight
            self.progressedTrackHeightConstraint?.constant = Metrics.restingTrackHeight
            self.layoutIfNeeded()
        }
        sendActions(for: .editingDidEnd)
    }

    override func cancelTracking(with event: UIEvent?) {
        endTracking(nil, with: event)
    }
}

extension ReaderSliderView {
    func move(toValue value: CGFloat) {
        currentValue = value
    }

    private func positionForValue(_ value: CGFloat) -> CGFloat {
        if direction == .forward {
            trackView.bounds.width * value
        } else {
            trackView.bounds.width - (trackView.bounds.width * value)
        }
    }

    private func boundValue(_ value: CGFloat, toLowerValue lowerValue: CGFloat, upperValue: CGFloat) -> CGFloat {
        min(max(value, lowerValue), upperValue)
    }
}
