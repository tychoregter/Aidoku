//
//  LibraryPageContextPreviewViewController.swift
//  Aidoku
//

import UIKit

final class LibraryPageContextPreviewViewController: UIViewController {
    private let mangaId: MangaIdentifier
    private let imageView = UIImageView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var loadTask: Task<Void, Never>?

    init(mangaId: MangaIdentifier) {
        self.mangaId = mangaId
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = CGSize(width: 300, height: 440)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        view.addSubview(imageView)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        loadTask = Task { [weak self] in
            guard let self else { return }
            let image = await LibraryPagePreviewCache.shared.image(for: mangaId)
            guard !Task.isCancelled else { return }
            activityIndicator.stopAnimating()
            imageView.image = image
            guard let image, image.size.width > 0, image.size.height > 0 else { return }

            // Scale both dimensions by the same amount. Clamping width and height
            // independently can turn unusually wide or tall pages into square previews.
            preferredContentSize = Self.previewSize(for: image.size)
        }
    }

    private static func previewSize(for imageSize: CGSize) -> CGSize {
        let maximumSize = CGSize(width: 340, height: 520)
        let scale = min(
            maximumSize.width / imageSize.width,
            maximumSize.height / imageSize.height,
            1
        )
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    deinit {
        loadTask?.cancel()
    }
}
