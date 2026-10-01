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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        toolbarTransitionState.isLeaving = false
        toolbarTransitionState.isEntering = animated
        if animated, let transitionCoordinator {
            transitionCoordinator.animate(alongsideTransition: nil) { [weak self] _ in
                self?.toolbarTransitionState.isEntering = false
            }
        } else {
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

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        toolbarTransitionState.isLeaving = true

        if let previousTabBarAppearance, let tabBar = tabBarController?.tabBar {
            tabBar.standardAppearance = previousTabBarAppearance.standard
            tabBar.scrollEdgeAppearance = previousTabBarAppearance.scrollEdge
            tabBar.isTranslucent = previousTabBarAppearance.isTranslucent
            self.previousTabBarAppearance = nil
        }
    }
}
