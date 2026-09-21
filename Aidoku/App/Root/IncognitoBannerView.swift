//
//  IncognitoBannerView.swift
//  Aidoku
//
//  Created by Skitty on 12/15/25.
//

import UIKit

class IncognitoBannerView: UIView {
    private var notificationTokens: [NSObjectProtocol] = []
    private var readerBarsHidden = false

    private lazy var iconView: UIImageView = {
        let iconView = UIImageView()
        let config = UIImage.SymbolConfiguration(font: UIFont.preferredFont(forTextStyle: .caption1))
        iconView.image = UIImage(systemName: "eye.slash", withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
        iconView.tintColor = .label
        return iconView
    }()

    private lazy var textLabel: UILabel = {
        let textLabel = UILabel()
        textLabel.text = NSLocalizedString("INCOGNITO_MODE")
        textLabel.textColor = .label
        textLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        return textLabel
    }()

    private var stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.alignment = .center
        return stackView
    }()

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        configure()
        constrain()
        observeReaderBars()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }

    func configure() {
        backgroundColor = .init(dynamicProvider: { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? .systemGray3
                : .systemGray5
        })
        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(textLabel)
        addSubview(stackView)
    }

    private func observeReaderBars() {
        let center = NotificationCenter.default
        notificationTokens.append(
            center.addObserver(forName: .readerHidingBars, object: nil, queue: .main) { [weak self] notification in
                guard AppSettings.general.incognitoMode.get() else { return }
                let immediate = notification.object as? Bool ?? false
                self?.setReaderBarsHidden(true, animated: !immediate)
            }
        )
        notificationTokens.append(
            center.addObserver(forName: .readerShowingBars, object: nil, queue: .main) { [weak self] _ in
                self?.setReaderBarsHidden(false, animated: true)
            }
        )
    }

    private func setReaderBarsHidden(_ hidden: Bool, animated: Bool) {
        guard readerBarsHidden != hidden else { return }
        readerBarsHidden = hidden

        let update = { [weak self] in
            guard let self else { return }
            self.backgroundColor = hidden ? .black : UIColor { traits in
                traits.userInterfaceStyle == .dark ? .systemGray3 : .systemGray5
            }
        }
        if animated {
            UIView.animate(
                withDuration: CATransaction.animationDuration(),
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: update
            )
        } else {
            update()
        }
    }

    func constrain() {
        stackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor)
        ])
    }
}
