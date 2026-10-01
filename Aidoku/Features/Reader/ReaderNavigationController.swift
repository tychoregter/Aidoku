//
//  ReaderNavigationController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/23/21.
//

import SwiftUI
import AidokuRunner

final class ReaderTransitionSource {
    weak var viewController: UIViewController?

    init(_ viewController: UIViewController? = nil) {
        self.viewController = viewController
    }
}

class ReaderNavigationController: UINavigationController {
    let mangaInfo: MangaInfo?
    init(readerViewController: ReaderViewController, mangaInfo: MangaInfo? = nil) {
        self.mangaInfo = mangaInfo
        super.init(rootViewController: readerViewController)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var childForStatusBarHidden: UIViewController? {
        topViewController
    }

    override var childForStatusBarStyle: UIViewController? {
        topViewController
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        switch UserDefaults.standard.string(forKey: "Reader.orientation") {
            case "device": .all
            case "portrait": .portrait
            case "landscape": .landscape
            default: .all
        }
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        (topViewController as? ReaderViewController)?.removeOpeningTransitionCornerMaskImmediately()
        super.dismiss(animated: flag, completion: completion)
    }
}

struct SwiftUIReaderNavigationController: View {
    let source: AidokuRunner.Source?
    let manga: AidokuRunner.Manga
    let chapter: AidokuRunner.Chapter
    var startPage: Int?
    var transitionSource: ReaderTransitionSource?

    @State private var interfaceOrientations: UIInterfaceOrientationMask?

    init(
        source: AidokuRunner.Source?,
        manga: AidokuRunner.Manga,
        chapter: AidokuRunner.Chapter,
        startPage: Int? = nil,
        transitionSource: ReaderTransitionSource? = nil
    ) {
        self.source = source
        self.manga = manga
        self.chapter = chapter
        self.startPage = startPage
        self.transitionSource = transitionSource

        let interfaceOrientations: UIInterfaceOrientationMask
        switch UserDefaults.standard.string(forKey: "Reader.orientation") {
            case "device": interfaceOrientations = .all
            case "portrait": interfaceOrientations = .portrait
            case "landscape": interfaceOrientations = .landscape
            default: interfaceOrientations = .all
        }
        _interfaceOrientations = State(initialValue: interfaceOrientations)
    }

    var body: some View {
        _SwiftUIReaderNavigationController(
            source: source,
            manga: manga,
            chapter: chapter,
            startPage: startPage,
            transitionSource: transitionSource
        )
            .interfaceOrientations(interfaceOrientations)
            .onReceive(NotificationCenter.default.publisher(for: .readerOrientation)) { _ in
                switch UserDefaults.standard.string(forKey: "Reader.orientation") {
                    case "device": interfaceOrientations = .all
                    case "portrait": interfaceOrientations = .portrait
                    case "landscape": interfaceOrientations = .landscape
                    default: interfaceOrientations = .all
                }
            }
    }
}

private struct _SwiftUIReaderNavigationController: UIViewControllerRepresentable {
    let source: AidokuRunner.Source?
    let manga: AidokuRunner.Manga
    let chapter: AidokuRunner.Chapter
    var startPage: Int?
    var transitionSource: ReaderTransitionSource?

    final class Coordinator {
        var nav: ReaderNavigationController?
        var reader: ReaderViewController?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> ReaderNavigationController {
        if let nav = context.coordinator.nav { return nav }

        let reader = ReaderViewController(
            source: source,
            manga: manga,
            chapter: chapter,
            startPage: startPage
        )
        reader.openingTransitionSourceViewController = transitionSource?.viewController
        let nav = ReaderNavigationController(readerViewController: reader)
        context.coordinator.reader = reader
        context.coordinator.nav = nav
        return nav
    }

    func updateUIViewController(_ uiViewController: ReaderNavigationController, context: Context) {
        guard let reader = context.coordinator.reader else { return }
        reader.openingTransitionSourceViewController = transitionSource?.viewController

        // make a fresh reader instance if needed
        if reader.manga.key != manga.key || reader.manga.sourceKey != manga.sourceKey {
            let newReader = ReaderViewController(
                source: source,
                manga: manga,
                chapter: chapter,
                startPage: startPage
            )
            newReader.openingTransitionSourceViewController = transitionSource?.viewController
            context.coordinator.reader = newReader
            uiViewController.setViewControllers([newReader], animated: false)
        } else {
            // Otherwise, update the existing reader instance
            if reader.chapter != chapter {
                reader.setChapter(chapter)
                reader.loadCurrentChapter()
            }
        }
    }
}
