//
//  MangaViewController.swift
//  Aidoku
//
//  Created by Skitty on 7/29/25.
//

import AidokuRunner
import SwiftUI

final class MangaToolbarTransitionState: ObservableObject {
    @Published var isLeaving = false
    @Published var isEntering = false
}

class MangaViewController: UIHostingController<MangaView> {
    let manga: AidokuRunner.Manga
    let mangaInfo: MangaInfo?
    private let toolbarTransitionState: MangaToolbarTransitionState
    private var previousTabBarAppearance: (
        standard: UITabBarAppearance,
        scrollEdge: UITabBarAppearance?,
        isTranslucent: Bool
    )?

    convenience init(
        source: AidokuRunner.Source? = nil,
        manga: MangaInfo,
        parent: UIViewController?,
        chapterKey: String? = nil,
        openAction: MangaView.OpenAction? = nil,
    ) {
        self.init(
            source: source,
            manga: manga.toManga().toNew(),
            parent: parent,
            chapterKey: chapterKey,
            openAction: openAction,
            mangaInfo: manga
        )
    }

    init(
        source: AidokuRunner.Source? = nil,
        manga: AidokuRunner.Manga,
        parent: UIViewController?,
        chapterKey: String? = nil,
        openAction: MangaView.OpenAction? = nil,
        mangaInfo: MangaInfo? = nil
    ) {
        self.manga = manga
        self.mangaInfo = mangaInfo
        let toolbarTransitionState = MangaToolbarTransitionState()
        let readerTransitionSource = ReaderTransitionSource()
        self.toolbarTransitionState = toolbarTransitionState
        super.init(rootView: MangaView(
            source: source,
            manga: manga,
            path: NavigationCoordinator(rootViewController: parent),
            chapterKey: chapterKey,
            openAction: openAction,
            toolbarTransitionState: toolbarTransitionState,
            readerTransitionSource: readerTransitionSource
        ))
        readerTransitionSource.viewController = self

        navigationItem.title = manga.title
        navigationItem.titleView = UIView() // hide navigation bar title
        navigationItem.largeTitleDisplayMode = .never
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Lay out SwiftUI's destination before UIKit snapshots it for the zoom.
    /// Otherwise the first rendered frame can be the full-size page.
    func prepareForZoomTransition(in navigationController: UINavigationController?) {
        guard let navigationController else { return }
        toolbarTransitionState.isEntering = true
        loadViewIfNeeded()
        view.frame = navigationController.view.bounds
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        toolbarTransitionState.isLeaving = false
        toolbarTransitionState.isEntering = animated
        super.viewWillAppear(animated)
        if animated, let transitionCoordinator {
            transitionCoordinator.animate(alongsideTransition: nil) { [weak self] _ in
                self?.toolbarTransitionState.isEntering = false
            }
        } else if !animated {
            toolbarTransitionState.isEntering = false
        }

        guard let tabBar = tabBarController?.tabBar else { return }
        if previousTabBarAppearance == nil {
            previousTabBarAppearance = (
                tabBar.standardAppearance,
                tabBar.scrollEdgeAppearance,
                tabBar.isTranslucent
            )
        }

        // Keep the system's floating controls, but let the scrolling page show
        // through the bar in both its normal and scroll-edge states.
        let appearance = (tabBar.standardAppearance.copy() as? UITabBarAppearance) ?? UITabBarAppearance()
        appearance.backgroundColor = .clear
        appearance.backgroundEffect = nil
        appearance.backgroundImage = nil
        appearance.shadowColor = .clear
        appearance.shadowImage = nil
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.isTranslucent = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        toolbarTransitionState.isEntering = false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        toolbarTransitionState.isLeaving = true

        if #available(iOS 26.0, *), isMovingFromParent {
            // SwiftUI's onDisappear can run before or during the pop. Clear the
            // shared bar again when the transition finishes, after its toolbar
            // items have been removed, so Library keeps its own appearance.
            let navigationBar = navigationController?.navigationBar
            transitionCoordinator?.animate(alongsideTransition: nil) { context in
                guard !context.isCancelled else { return }
                navigationBar?.overrideUserInterfaceStyle = .unspecified
                navigationBar?.tintColor = nil
            }
        }

        if let previousTabBarAppearance, let tabBar = tabBarController?.tabBar {
            tabBar.standardAppearance = previousTabBarAppearance.standard
            tabBar.scrollEdgeAppearance = previousTabBarAppearance.scrollEdge
            tabBar.isTranslucent = previousTabBarAppearance.isTranslucent
            self.previousTabBarAppearance = nil
        }
    }
}
